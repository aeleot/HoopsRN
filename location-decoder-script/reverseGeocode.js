#!/usr/bin/env node

/**
 * Reverse Geocoding Script for Basketball Courts
 *
 * Reverse geocodes coordinates using OpenStreetMap Nominatim API
 * and updates court names and addresses accordingly.
 *
 * Features:
 * - Rate limiting (1 request/sec, 10 sec wait for 429)
 * - Exponential backoff retry logic (3 attempts)
 * - Progress persistence (resumes from courts_updated.json)
 * - Facility name detection (parks, recreation centers, schools, etc.)
 * - Real-time progress display and final summary
 */

const axios = require('axios');
const fs = require('fs/promises');
const path = require('path');

// Configuration constants
const CONFIG = {
  INPUT_FILE: 'hoopr/Resources/courts.json',
  OUTPUT_FILE: 'hoopr/Resources/courts_updated.json',
  NOMINATIM_API: 'https://nominatim.openstreetmap.org/reverse',
  RATE_LIMIT_MS: 1000, // 1 second between requests
  RATE_LIMIT_429_MS: 10000, // 10 seconds after 429 error
  MAX_RETRIES: 3,
  USER_AGENT: 'BasketballCourtGeocoder/1.0 (https://github.com)',
};

// Facility type keywords to extract from display_name
const FACILITY_KEYWORDS = [
  'park',
  'recreation center',
  'rec center',
  'community center',
  'gym',
  'gymnasium',
  'ymca',
  'y.m.c.a',
  'sports complex',
  'sports center',
  'sports facility',
  'school',
  'high school',
  'elementary school',
  'middle school',
  'college',
  'university',
  'court',
  'field',
  'arena',
];

/**
 * Sleep for a specified duration in milliseconds
 */
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Extract facility name from Nominatim display_name
 * Returns the most relevant facility name or null if none found
 */
function extractFacilityName(displayName) {
  if (!displayName) return null;

  const nameParts = displayName.split(',');

  // Check each part of the address for facility keywords
  for (const part of nameParts) {
    const trimmedPart = part.trim().toLowerCase();

    // Check if this part contains any facility keyword
    for (const keyword of FACILITY_KEYWORDS) {
      if (trimmedPart.includes(keyword)) {
        // Return the original part (with proper casing)
        const originalPart = part.trim();

        // If it's just "Basketball Court", skip it
        if (originalPart.toLowerCase() === 'basketball court') {
          continue;
        }

        // Add "Basketball Court" if the part doesn't already mention court/field/etc
        const hasCourtType = /(court|field|gym|arena)$/i.test(originalPart);
        if (!hasCourtType && keyword !== 'court' && keyword !== 'field') {
          return `${originalPart} Basketball Court`;
        }

        return originalPart;
      }
    }
  }

  return null;
}

/**
 * Perform reverse geocoding with retry logic and rate limiting
 * Returns { address, facilityName } or null on failure
 */
async function reverseGeocode(latitude, longitude, retryCount = 0) {
  try {
    // Rate limiting: wait 1 second between requests
    await sleep(CONFIG.RATE_LIMIT_MS);

    const response = await axios.get(CONFIG.NOMINATIM_API, {
      params: {
        lat: latitude,
        lon: longitude,
        format: 'json',
      },
      headers: {
        'User-Agent': CONFIG.USER_AGENT,
      },
      timeout: 10000, // 10 second timeout
    });

    if (response.status === 200 && response.data) {
      const displayName = response.data.display_name || '';
      const facilityName = extractFacilityName(displayName);

      return {
        address: displayName,
        facilityName,
      };
    }

    return null;
  } catch (error) {
    // Handle 429 Too Many Requests with longer wait
    if (error.response?.status === 429) {
      console.log(`  ⚠ Rate limited (429). Waiting 10 seconds...`);
      await sleep(CONFIG.RATE_LIMIT_429_MS);

      if (retryCount < CONFIG.MAX_RETRIES) {
        return reverseGeocode(latitude, longitude, retryCount + 1);
      }
      throw new Error('Max retries exceeded after rate limiting');
    }

    // Retry with exponential backoff for other errors
    if (retryCount < CONFIG.MAX_RETRIES) {
      const backoffMs = Math.pow(2, retryCount) * 1000;
      await sleep(backoffMs);
      return reverseGeocode(latitude, longitude, retryCount + 1);
    }

    throw error;
  }
}

/**
 * Read input file, preferring courts_updated.json if it exists
 * Returns { records, startIndex }
 */
async function loadInputFile() {
  try {
    // Check if we have a progress file to resume from
    try {
      const updatedData = JSON.parse(
        await fs.readFile(CONFIG.OUTPUT_FILE, 'utf8')
      );

      console.log(`\n📋 Found existing progress file (${CONFIG.OUTPUT_FILE})`);
      console.log(`   Resuming from record ${updatedData.length}...\n`);

      return {
        records: updatedData,
        startIndex: updatedData.length,
      };
    } catch (err) {
      // Output file doesn't exist or can't be read, start fresh
      const inputData = JSON.parse(
        await fs.readFile(CONFIG.INPUT_FILE, 'utf8')
      );

      console.log(`\n📋 Loaded ${inputData.length} records from ${CONFIG.INPUT_FILE}\n`);

      return {
        records: inputData,
        startIndex: 0,
      };
    }
  } catch (error) {
    console.error(`❌ Error loading input file: ${error.message}`);
    process.exit(1);
  }
}

/**
 * Save current progress to output file
 */
async function saveProgress(records) {
  try {
    await fs.writeFile(
      CONFIG.OUTPUT_FILE,
      JSON.stringify(records, null, 2),
      'utf8'
    );
  } catch (error) {
    console.error(`❌ Error saving progress: ${error.message}`);
  }
}

/**
 * Main processing function
 */
async function main() {
  const startTime = Date.now();
  console.log('🏀 Basketball Court Reverse Geocoder');
  console.log('=====================================\n');

  // Load input data
  const { records, startIndex } = await loadInputFile();
  const totalRecords = records.length;

  // Track statistics
  let successCount = 0;
  let skippedCount = 0;
  let failedCount = 0;

  // Process each record
  for (let i = startIndex; i < records.length; i++) {
    const record = records[i];
    const progress = `[${i + 1}/${totalRecords}]`;

    // Skip records that already have an address
    if (record.address && record.address.trim() !== '') {
      console.log(`${progress} ⏭  SKIP (already has address): ${record.name}`);
      skippedCount++;
      continue;
    }

    try {
      const result = await reverseGeocode(record.latitude, record.longitude);

      if (result) {
        // Update record with geocoding results
        record.address = result.address;
        if (result.facilityName) {
          record.name = result.facilityName;
        }

        console.log(`${progress} ✅ ${record.name}`);
        successCount++;
      } else {
        console.log(`${progress} ❌ FAILED: No data returned for ${record.name}`);
        failedCount++;
      }
    } catch (error) {
      console.log(`${progress} ❌ FAILED: ${error.message} (${record.name})`);
      failedCount++;
    }

    // Save progress after each successful update
    await saveProgress(records);
  }

  // Calculate execution time
  const endTime = Date.now();
  const executionTime = ((endTime - startTime) / 1000).toFixed(2);

  // Final save
  await saveProgress(records);

  // Print summary
  console.log('\n=====================================');
  console.log('📊 Summary');
  console.log('=====================================');
  console.log(`Total Records:      ${totalRecords}`);
  console.log(`✅ Geocoded:        ${successCount}`);
  console.log(`⏭  Skipped:         ${skippedCount}`);
  console.log(`❌ Failed:          ${failedCount}`);
  console.log(`⏱  Execution Time:  ${executionTime}s`);
  console.log('=====================================\n');
  console.log(`💾 Results saved to ${CONFIG.OUTPUT_FILE}\n`);

  // Exit with error code if any records failed
  if (failedCount > 0) {
    process.exit(1);
  }
}

// Run the script
main().catch(error => {
  console.error('❌ Fatal error:', error.message);
  process.exit(1);
});
