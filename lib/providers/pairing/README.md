# Pairing System Architecture

╔══════════════════════════════════════════════════════════════════════════════╗

║                           PAIRING SYSTEM ARCHITECTURE                        ║

╠══════════════════════════════════════════════════════════════════════════════╣

║                                                                              ║

║  CORE CONCEPTS:                                                              ║

║  ──────────────                                                              ║

║  • Sessions are created on demand when the user explicitly creates one       ║

║    (via Settings > Create Pairing Session). No automatic session creation.   ║

║                                                                              ║

║  • Devices start without a session. They operate in "primary" mode but      ║

║    have no active session until one is created.                              ║

║                                                                              ║

║  • When a device creates a session, it becomes the primary device for that   ║

║    session and can share it via QR code.                                     ║

║                                                                              ║

║  • In a pairing:                                                             ║

║    - The primary device shares its session via QR code.                      ║

║    - The secondary device joins the primary's session and uses it for data   ║

║      display. Secondary devices do NOT maintain their own local session.     ║

║                                                                              ║

║  PAIRING FLOW:                                                               ║

║  ─────────────                                                               ║

║  1. Device A starts app:                                                     ║

║     - Starts in primary mode with no session                                 ║

║     - User creates pairing session "A-session" via Settings                  ║

║     - Device A becomes primary with localSessionToken = "A-session"         ║

║     - Uses "A-session" as effective session                                  ║

║                                                                              ║

║  2. Device B starts app:                                                     ║

║     - Starts in primary mode with no session                                 ║

║     - No local session created (sessions are on-demand only)                ║

║                                                                              ║

║  3. Device B scans Device A's QR code ("A-session"):                         ║

║     - Device B becomes secondary                                             ║

║     - Clears any local session (localSessionToken = null)                    ║

║     - Sets remoteSessionToken = "A-session"                                  ║

║     - Uses "A-session" as effective session                                  ║

║                                                                              ║

║  SESSION TYPES:                                                              ║

║  ──────────────                                                              ║

║  • LOCAL SESSION: Session created by this device (on-demand only)            ║

║    - Device owns and manages this session                                    ║

║    - localSessionToken points to this device's session (null if not created) ║

║    - Only exists when user explicitly creates a pairing session              ║

║    - Represented by localSessionProvider                                     ║

║                                                                              ║

║  • REMOTE SESSION: Session joined by scanning QR code (when secondary)       ║

║    - Device participates in someone else's session                           ║

║    - remoteSessionToken points to joined session (null when primary)         ║

║    - Represented by remoteSessionProvider                                    ║

║                                                                              ║

║  • EFFECTIVE SESSION: The session this device is currently using             ║

║    - remoteSessionToken when secondary, localSessionToken when primary       ║

║    - Represented by effectiveSessionProvider                                 ║

║                                                                              ║

║  ROLES:                                                                      ║

║  ──────                                                                      ║

║  • primary: Default role when not paired. May have a local session if        ║

║    one was created on-demand, or no session if none created yet.             ║

║  • secondary: Using remote session (joined via QR code scan)                 ║

║                                                                              ║

║  REALTIME DATABASE REPOSITORY:                                              ║

║  ─────────────────────────────                                               ║

║  • realtimeDatabaseRepositoryProvider provides access to Firebase operations ║

║  • All session providers use realtimeDb.getSessionDataStream(token)         ║

║  • Primary and secondary devices read from SAME Firebase document when paired║

║  • Session data includes: anchor, position, alarms, monitoring status     ║

║                                                                              ║

║  STATE MANAGEMENT:                                                           ║

║  ─────────────────                                                           ║

║  • pairingSessionStateProvider: Current role and session tokens              ║

║  • sessionToken (computed): Effective session = remote ?? local              ║

║  • sessionToken may be null if no session has been created or joined         ║

║  • Role determines behavior, but session operations require a valid token     ║

║                                                                              ║

╚══════════════════════════════════════════════════════════════════════════════╝

