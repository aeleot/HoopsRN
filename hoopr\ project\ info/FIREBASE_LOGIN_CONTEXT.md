# Firebase Login Implementation Context

**Created:** 2026-07-24
**Purpose:** Specification and roadmap for integrating Firebase Authentication into Hoopr
**Status:** Planning (not yet implemented)

---

## Overview

This document outlines the architecture, file structure, and implementation details for adding user authentication to Hoopr using Firebase Authentication. The goal is to replace the hardcoded "User1" username with proper login/signup flow, session management, and secure user data persistence.

---

## Firebase Setup & Configuration

### Prerequisites
- Firebase project created at [console.firebase.google.com](https://console.firebase.google.com)
- iOS app registered in Firebase console
- GoogleService-Info.plist downloaded and added to Xcode project
- Firebase SDK dependencies installed

### Dependencies
Add via Swift Package Manager:
- **FirebaseAuth** — User authentication (email/password, Google Sign-In)
- **FirebaseFirestore** — User profile storage
- **FirebaseStorage** — Profile pictures (future enhancement)

Alternatively, use CocoaPods:
```ruby
pod 'Firebase/Auth'
pod 'Firebase/Firestore'
pod 'GoogleSignIn' # For Google Sign-In button
```

### Xcode Project Configuration

**File:** `hooprApp.swift`

```swift
import Firebase

@main
struct hooprApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var sharedModelContainer: ModelContainer = { ... }()
    
    var body: some Scene {
        WindowGroup {
            ContentState()  // New root wrapper
        }
        .modelContainer(sharedModelContainer)
    }
}
```

New root view `ContentState` handles auth state and navigation to either LoginView or MainTabView.

---

## Authentication Architecture

### AuthManager — Firebase Integration

**File:** `Managers/AuthManager.swift`

Central service managing Firebase authentication state and user profile data.

```swift
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AuthManager: NSObject, ObservableObject {
    @Published var currentUser: HooprUser?
    @Published var authState: AuthState = .unknown
    @Published var errorMessage: String?
    
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    enum AuthState {
        case unknown          // Initial state, checking session
        case unauthenticated  // User not logged in
        case authenticated    // User logged in
        case loading          // Auth operation in progress
    }
    
    override init() {
        super.init()
        setupAuthStateListener()
    }
    
    // MARK: - Auth State Listening
    
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user = user {
                    self?.authState = .authenticated
                    await self?.loadUserProfile(uid: user.uid, email: user.email ?? "")
                } else {
                    self?.authState = .unauthenticated
                    self?.currentUser = nil
                }
            }
        }
    }
    
    // MARK: - Sign Up
    
    func signUp(email: String, password: String, displayName: String) async -> Bool {
        authState = .loading
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // Create user profile in Firestore
            let hooprUser = HooprUser(
                uid: result.user.uid,
                email: email,
                displayName: displayName,
                createdAt: Date(),
                favoritesCourt: []
            )
            
            try await Firestore.firestore()
                .collection("users")
                .document(result.user.uid)
                .setData(from: hooprUser)
            
            currentUser = hooprUser
            authState = .authenticated
            return true
        } catch {
            errorMessage = error.localizedDescription
            authState = .unauthenticated
            return false
        }
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async -> Bool {
        authState = .loading
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            await loadUserProfile(uid: result.user.uid, email: result.user.email ?? "")
            authState = .authenticated
            return true
        } catch {
            errorMessage = error.localizedDescription
            authState = .unauthenticated
            return false
        }
    }
    
    // MARK: - Google Sign-In
    
    func signInWithGoogle(idToken: String, accessToken: String) async -> Bool {
        authState = .loading
        do {
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            let result = try await Auth.auth().signIn(with: credential)
            
            // Check if user profile exists; create if not
            let docRef = Firestore.firestore().collection("users").document(result.user.uid)
            let snapshot = try await docRef.getDocument()
            
            if !snapshot.exists {
                let hooprUser = HooprUser(
                    uid: result.user.uid,
                    email: result.user.email ?? "",
                    displayName: result.user.displayName ?? "User",
                    createdAt: Date(),
                    favoritesCourt: []
                )
                try await docRef.setData(from: hooprUser)
                currentUser = hooprUser
            } else {
                let hooprUser = try snapshot.data(as: HooprUser.self)
                currentUser = hooprUser
            }
            
            authState = .authenticated
            return true
        } catch {
            errorMessage = error.localizedDescription
            authState = .unauthenticated
            return false
        }
    }
    
    // MARK: - Load User Profile
    
    private func loadUserProfile(uid: String, email: String) async {
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .getDocument()
            
            if let hooprUser = try snapshot.data(as: HooprUser?.self) {
                currentUser = hooprUser
            } else {
                // Fallback profile if Firestore record not yet created
                currentUser = HooprUser(
                    uid: uid,
                    email: email,
                    displayName: "User",
                    createdAt: Date(),
                    favoritesCourt: []
                )
            }
        } catch {
            errorMessage = "Failed to load user profile: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() throws {
        try Auth.auth().signOut()
        currentUser = nil
        authState = .unauthenticated
    }
    
    // MARK: - Password Reset
    
    func sendPasswordReset(email: String) async -> Bool {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
}
```

### HooprUser — User Data Model

**File:** `Models/HooprUser.swift`

```swift
import Foundation
import FirebaseFirestoreSwift

struct HooprUser: Identifiable, Codable, Sendable {
    @DocumentID var id: String?
    
    let uid: String              // Firebase UID
    let email: String
    let displayName: String
    let createdAt: Date
    var favoriteCourts: [String] // Array of Court IDs
    
    var initials: String {
        displayName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
    }
}
```

---

## Navigation & UI Flow

### Root Navigation

**File:** `ContentState.swift`

New root view that observes `AuthManager.authState` and routes accordingly.

```swift
import SwiftUI

struct ContentState: View {
    @StateObject private var authManager = AuthManager()
    
    var body: some View {
        Group {
            switch authManager.authState {
            case .unknown, .loading:
                SplashScreen()
            case .unauthenticated:
                LoginView()
                    .environmentObject(authManager)
            case .authenticated:
                MainTabView()
                    .environmentObject(authManager)
            }
        }
    }
}
```

### Splash Screen (Loading State)

**File:** `Views/SplashScreen.swift`

Shown on app launch while Firebase checks for existing session.

```swift
import SwiftUI

struct SplashScreen: View {
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "basketball.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.hooprOrange)
            Text("Hoopr")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.black)
            Spacer()
            ProgressView()
                .tint(Color.hooprOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}
```

### Login View

**File:** `Views/Auth/LoginView.swift`

Email/password login with Google Sign-In option.

```swift
import SwiftUI
import GoogleSignIn

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showSignUp = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "basketball.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.hooprOrange)
                    Text("Hoopr")
                        .font(.system(size: 28, weight: .bold))
                    Text("Find courts. Play ball.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.hooprSecondaryText)
                }
                
                Spacer()
                
                // Form
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .padding(12)
                        .background(Color.hooprLightGray)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    SecureField("Password", text: $password)
                        .padding(12)
                        .background(Color.hooprLightGray)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                // Error message
                if let error = authManager.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.hooprRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Sign In Button
                Button(action: { Task { await handleSignIn() } }) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign In")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.hooprOrange)
                .foregroundStyle(.white)
                .font(.system(size: 16, weight: .semibold))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                
                // Sign Up Link
                HStack {
                    Text("Don't have an account?")
                    NavigationLink("Sign up", destination: SignUpView())
                        .foregroundStyle(Color.hooprOrange)
                }
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .center)
                
                Spacer()
                
                // Google Sign-In
                Button(action: { Task { await handleGoogleSignIn() } }) {
                    HStack {
                        Image("google_logo") // Add Google logo to assets
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text("Continue with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.white)
                    .foregroundStyle(.black)
                    .font(.system(size: 14, weight: .semibold))
                    .border(Color.hooprBorderGray, width: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                Spacer()
            }
            .padding(24)
        }
    }
    
    private func handleSignIn() async {
        isLoading = true
        let success = await authManager.signIn(email: email, password: password)
        isLoading = false
        if success {
            print("[Hoopr Auth] User signed in: \(email)")
        }
    }
    
    private func handleGoogleSignIn() async {
        // Integration with GoogleSignIn SDK
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }
        let config = GIDConfiguration(clientID: clientID)
        
        GIDSignIn.sharedInstance.configuration = config
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else { return }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            guard let result = result else {
                authManager.errorMessage = error?.localizedDescription ?? "Google Sign-In failed"
                return
            }
            
            guard let idToken = result.user.idToken?.tokenString else { return }
            let accessToken = result.user.accessToken.tokenString
            
            Task {
                let success = await authManager.signInWithGoogle(idToken: idToken, accessToken: accessToken)
                if success {
                    print("[Hoopr Auth] User signed in with Google")
                }
            }
        }
    }
}
```

### Sign Up View

**File:** `Views/Auth/SignUpView.swift`

Registration form for new users.

```swift
import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    
    var isFormValid: Bool {
        !displayName.isEmpty && 
        !email.isEmpty && 
        password == confirmPassword && 
        password.count >= 6
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.black)
                }
                Spacer()
                Text("Create Account")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Rectangle().frame(width: 32, height: 1).opacity(0)
            }
            
            // Form
            VStack(spacing: 12) {
                TextField("Full Name", text: $displayName)
                    .padding(12)
                    .background(Color.hooprLightGray)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding(12)
                    .background(Color.hooprLightGray)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                SecureField("Password (min 6 chars)", text: $password)
                    .padding(12)
                    .background(Color.hooprLightGray)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                SecureField("Confirm Password", text: $confirmPassword)
                    .padding(12)
                    .background(Color.hooprLightGray)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Error message
            if let error = authManager.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.hooprRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Sign Up Button
            Button(action: { Task { await handleSignUp() } }) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Create Account")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color.hooprOrange)
            .foregroundStyle(.white)
            .font(.system(size: 16, weight: .semibold))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(isLoading || !isFormValid)
            
            Spacer()
        }
        .padding(24)
        .navigationBarBackButtonHidden(true)
    }
    
    private func handleSignUp() async {
        isLoading = true
        let success = await authManager.signUp(email: email, password: password, displayName: displayName)
        isLoading = false
        if success {
            print("[Hoopr Auth] User registered: \(email)")
            dismiss()
        }
    }
}
```

---

## Changes to Existing Files

### MainTabView.swift

**Changes:**
1. Replace hardcoded `userName = "User1"` with `authManager.currentUser?.displayName ?? "User"`
2. Add `@EnvironmentObject var authManager: AuthManager` to receive auth state
3. Add sign-out button in ProfileTab or settings menu
4. Update header greeting to use dynamic username

```swift
struct MainTabView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var locationManager = LocationManager()
    @State private var selectedTab = 0
    @State private var showProfile = false
    
    private var userName: String {
        authManager.currentUser?.displayName ?? "User"
    }
    
    var body: some View {
        // ... existing header structure ...
        HStack {
            Text("Let's go hoop \(userName).")
                .font(.system(size: 28))
                .foregroundStyle(.black)
            Spacer()
            // Profile button...
        }
        // ... rest of view ...
    }
}
```

### ProfileTab.swift

**Changes:**
1. Replace placeholder with actual profile view
2. Display user info: display name, email, join date
3. Add "Sign Out" button
4. Show favorite courts (future feature)
5. Display profile picture (future enhancement)

```swift
struct ProfileTab: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showSignOutConfirm = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Profile") {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.hooprOrange)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(authManager.currentUser?.initials ?? "U")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 16, weight: .semibold))
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authManager.currentUser?.displayName ?? "User")
                                .font(.system(size: 16, weight: .semibold))
                            Text(authManager.currentUser?.email ?? "")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.hooprSecondaryText)
                        }
                        Spacer()
                    }
                }
                
                Section("Account") {
                    NavigationLink(destination: EditProfileView()) {
                        Label("Edit Profile", systemImage: "pencil")
                    }
                    
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gear")
                    }
                }
                
                Section {
                    Button(role: .destructive, action: { showSignOutConfirm = true }) {
                        Label("Sign Out", systemImage: "door.left.hand.open")
                    }
                }
            }
            .navigationTitle("Profile")
        }
        .alert("Sign Out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) { handleSignOut() }
        } message: {
            Text("You'll need to sign in again to use Hoopr.")
        }
    }
    
    private func handleSignOut() {
        do {
            try authManager.signOut()
            print("[Hoopr Auth] User signed out")
        } catch {
            print("[Hoopr Auth] Sign out failed: \(error.localizedDescription)")
        }
    }
}
```

---

## Firestore Database Schema

### Users Collection

**Path:** `users/{uid}`

```json
{
  "uid": "firebase-uid-string",
  "email": "user@example.com",
  "displayName": "John Doe",
  "initials": "JD",
  "createdAt": "2026-07-24T12:00:00Z",
  "favoriteCourts": ["35.79150,-78.78110", "35.79200,-78.78200"],
  "updatedAt": "2026-07-24T12:00:00Z"
}
```

**Security Rules:**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own profile
    match /users/{uid} {
      allow read, write: if request.auth.uid == uid;
    }
    
    // Courts collection (read-only for all authenticated users)
    match /courts/{document=**} {
      allow read: if request.auth != null;
      allow write: if false;
    }
  }
}
```

---

## Error Handling & User Feedback

### Authentication Errors

**Common Firebase errors to handle:**
- `auth/invalid-email` — Email format invalid
- `auth/user-disabled` — Account disabled by admin
- `auth/user-not-found` — User doesn't exist (sign in)
- `auth/wrong-password` — Incorrect password
- `auth/email-already-in-use` — Email exists (sign up)
- `auth/weak-password` — Password too weak
- `auth/network-request-failed` — Network error
- `auth/too-many-requests` — Rate limited

Each error displayed via `authManager.errorMessage` property bound to UI.

### Offline Support

When user loses internet:
1. Auth state persists (Firebase caches session locally)
2. User can continue viewing cached court data
3. Sign out requires internet connection
4. New sign in/up requires internet (shows appropriate error)

---

## Session Persistence

### Auto Sign-In Flow

```
App Launch
  └─ hooprApp.init() calls FirebaseApp.configure()
  └─ ContentState renders
       └─ AuthManager.authState = .unknown
       └─ SplashScreen displays
       └─ AuthManager.setupAuthStateListener() checks for cached Firebase session
            └─ Auth.auth().addStateDidChangeListener fires
                 ├─ Firebase session exists? → authState = .authenticated
                 └─ No session? → authState = .unauthenticated
       └─ ContentState updates based on new authState
            ├─ If authenticated → MainTabView
            └─ If unauthenticated → LoginView
```

**Duration:** Session persists until:
1. User explicitly signs out
2. Firebase session expires (typically 1 hour inactivity)
3. App is uninstalled/reinstalled (clears auth cache)

---

## Console Logging for Auth Events

Add logging similar to court data flow:

```swift
// In AuthManager
print("[Hoopr Auth] Auth state changed: \(authState)")
print("[Hoopr Auth] User loaded: \(currentUser?.displayName ?? "Unknown")")
print("[Hoopr Auth] Sign in attempt: \(email)")
print("[Hoopr Auth] Sign out completed")
print("[Hoopr Auth] Google Sign-In initiated")
```

Logs help debug authentication flow in Xcode console.

---

## Future Enhancements

### Phase 2: User Profile Features
- Edit display name, bio, profile picture
- Favorite courts management
- View favorite courts on map
- Share profile with other players

### Phase 3: Social Features
- Add friends
- Follow other players
- See friends' check-ins on map
- Send messages

### Phase 4: Court Reviews & Ratings
- Rate courts (1-5 stars)
- Write reviews
- Upload court photos
- Mark courts as open/closed

### Phase 5: Account Security
- Email verification
- Two-factor authentication (2FA)
- Social login providers (Apple Sign-In, Facebook)
- Account recovery/password reset

---

## Testing Checklist

- [ ] Firebase project created and iOS app registered
- [ ] GoogleService-Info.plist added to Xcode project
- [ ] Firebase dependencies installed (SPM or CocoaPods)
- [ ] AuthManager created and tested
- [ ] LoginView displays and form validation works
- [ ] SignUpView displays and registration works
- [ ] Email/password login succeeds
- [ ] Google Sign-In flow works end-to-end
- [ ] User profile loads from Firestore
- [ ] Session persists across app relaunch
- [ ] Sign out clears session and redirects to LoginView
- [ ] Error messages display correctly for invalid inputs
- [ ] Password reset email flow works
- [ ] Offline sign in uses cached session
- [ ] Firestore security rules prevent unauthorized access
- [ ] Console logs show auth events clearly

---

## File Summary

**New Files to Create:**
- `ContentState.swift` — Root navigation based on auth state
- `Managers/AuthManager.swift` — Firebase authentication manager
- `Models/HooprUser.swift` — User data model
- `Views/SplashScreen.swift` — Loading state during auth check
- `Views/Auth/LoginView.swift` — Email/password login + Google Sign-In
- `Views/Auth/SignUpView.swift` — Registration form
- `Views/EditProfileView.swift` — Profile editing (future)
- `Views/SettingsView.swift` — App settings (future)
- `GoogleService-Info.plist` — Firebase configuration (downloaded from console)

**Files to Modify:**
- `hooprApp.swift` — Add `FirebaseApp.configure()`, change root view to `ContentState`
- `MainTabView.swift` — Add `@EnvironmentObject var authManager`, use dynamic username
- `ProfileTab.swift` — Replace placeholder with actual profile + sign out
- `Theme.swift` — Optional: add additional colors if needed

**Configuration:**
- Firebase console project setup
- iOS app registration in Firebase
- Firestore database initialization
- Firestore security rules configuration
- Google Sign-In configuration (OAuth consent screen)
- App signing configuration for Google Sign-In

---

## Migration Path

### From Current App to Firebase-Enabled App

1. **Week 1:** Firebase setup, AuthManager creation, testing auth flow
2. **Week 2:** LoginView, SignUpView UI and basic validation
3. **Week 3:** Integration with MainTabView, ProfileTab implementation
4. **Week 4:** Google Sign-In, session persistence, error handling
5. **Week 5:** Testing, documentation, deployment to TestFlight

---

## References

- [Firebase Authentication Documentation](https://firebase.google.com/docs/auth)
- [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios)
- [Firebase Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [SwiftUI + Firebase Integration](https://firebase.google.com/docs/firestore/quickstart#swift)
