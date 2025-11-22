# Firestore Security Rules

This document contains the Firestore security rules needed for the Anchor Alarm app's multi-device monitoring feature.

## Setup Instructions

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to **Firestore Database** → **Rules** tab
4. Replace the default rules with the rules below
5. Click **Publish**

## Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function to check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Sessions collection - for pairing and monitoring
    match /sessions/{sessionId} {
      // Allow read if authenticated (anyone can read with session token)
      allow read: if isAuthenticated();
      
      // Allow write if authenticated (primary device creates/updates)
      allow write: if isAuthenticated();
      
      // Allow updates to session data (anchor, boatPosition, etc.)
      allow update: if isAuthenticated();
      
      // Subcollections
      match /positions/{positionId} {
        // Allow read if authenticated
        allow read: if isAuthenticated();
        // Allow write if authenticated (primary device only)
        allow write: if isAuthenticated();
      }
      
      match /alarms/{alarmId} {
        // Allow read if authenticated
        allow read: if isAuthenticated();
        // Allow create if authenticated (primary device)
        allow create: if isAuthenticated();
        // Allow update if authenticated (any device can acknowledge)
        allow update: if isAuthenticated();
      }
    }
  }
}
```

## Alternative: More Restrictive Rules (Recommended for Production)

If you want more security, you can restrict writes to only the primary device by checking the `primaryDeviceId` field:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Helper to check if current user is primary device
    function isPrimaryDevice(sessionId) {
      return isAuthenticated() && 
             get(/databases/$(database)/documents/sessions/$(sessionId)).data.primaryDeviceId == request.auth.uid;
    }
    
    match /sessions/{sessionId} {
      // Anyone authenticated can read
      allow read: if isAuthenticated();
      
      // Only primary device can create/update session
      allow create: if isAuthenticated();
      allow update: if isAuthenticated() && 
                      (request.resource.data.primaryDeviceId == request.auth.uid ||
                       resource.data.primaryDeviceId == request.auth.uid);
      
      match /positions/{positionId} {
        allow read: if isAuthenticated();
        // Only primary device can write positions
        allow write: if isPrimaryDevice(sessionId);
      }
      
      match /alarms/{alarmId} {
        allow read: if isAuthenticated();
        allow create: if isPrimaryDevice(sessionId);
        // Any authenticated device can acknowledge
        allow update: if isAuthenticated();
      }
    }
  }
}
```

## Testing Rules

After publishing rules, test them:

1. **Test Read Access**: Try reading a session document
2. **Test Write Access**: Try creating a new session
3. **Test Update Access**: Try updating session data

## Troubleshooting

### Permission Denied Errors

If you're getting permission denied errors:

1. **Check Authentication**: Ensure the app is signed in anonymously
   - Check logs for "Signed in anonymously" message
   - Verify `FirebaseAuth.instance.currentUser` is not null

2. **Check Rules**: Verify rules are published in Firebase Console
   - Rules can take a few seconds to propagate
   - Try refreshing the app after publishing rules

3. **Check Collection Path**: Ensure you're writing to the correct path
   - Should be: `sessions/{sessionId}`
   - Not: `session/{sessionId}` or `sessions/{sessionId}/data`

4. **Check Field Names**: Ensure document structure matches what rules expect
   - Primary device ID should be in `primaryDeviceId` field

### Development vs Production

For development, you can use more permissive rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

⚠️ **Warning**: These rules allow any authenticated user to read/write everything. Only use for development!

## Notes

- The app uses **anonymous authentication** - no user accounts required
- Each device gets a unique anonymous UID when it signs in
- The `primaryDeviceId` field stores the UID of the primary device
- Secondary devices can read but should not write (enforced by app logic, not rules in MVP)

