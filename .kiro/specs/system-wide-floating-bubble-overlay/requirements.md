# Requirements Document

## Introduction

The LifeGuard360 app includes a floating bubble overlay feature designed to provide quick access to emergency SOS functionality from anywhere on the device. Currently, the bubble only appears within the Flutter app itself, not over other apps or the home screen. This bug prevents the core use case of system-wide emergency access, similar to Facebook Messenger chat heads.

The floating bubble uses `flutter_overlay_window: ^0.5.0` and has SYSTEM_ALERT_WINDOW permission declared, but the implementation relies on MainActivity to trigger the overlay, which only works when the Flutter app is in the foreground.

## Glossary

- **Flutter_Overlay_Window**: Plugin that enables system-wide overlays on Android using TYPE_APPLICATION_OVERLAY window type
- **System_Alert_Window**: Android permission required for drawing overlays on top of other apps
- **Chathead_Bubble**: The draggable floating bubble UI element that provides SOS functionality
- **Overlay_Service**: Android foreground service that manages the Flutter overlay lifecycle
- **MainActivity**: The main Flutter activity that currently controls overlay visibility
- **Background_Service**: The existing flutter_background_service that runs continuously
- **Overlay_Isolate**: Separate Dart isolate that runs the chathead overlay UI independently

## Requirements

### Requirement 1: System-Wide Overlay Visibility

**User Story:** As a user, I want the floating bubble to appear over ALL apps and the home screen, so that I can trigger emergency SOS from anywhere without opening the LifeGuard360 app.

#### Acceptance Criteria

1. WHEN the floating bubble is enabled and the user navigates to the home screen, THE System SHALL continue displaying the bubble over the home screen
2. WHEN the floating bubble is enabled and the user opens any third-party app, THE System SHALL continue displaying the bubble over that app
3. WHEN the user interacts with the bubble over another app, THE System SHALL respond to taps and drags without requiring the LifeGuard360 app to be in the foreground
4. WHEN the device is rebooted and the floating bubble was enabled before reboot, THE System SHALL automatically start the overlay after boot completion

### Requirement 2: Native Service Management

**User Story:** As a developer, I want the overlay to be managed by a native Android service independent of MainActivity, so that the overlay persists regardless of the main Flutter app's lifecycle state.

#### Acceptance Criteria

1. WHEN the floating bubble is enabled, THE Overlay_Service SHALL start as a foreground service independent of MainActivity
2. WHEN the main Flutter app is closed or destroyed, THE Overlay_Service SHALL continue running and displaying the bubble
3. WHEN the Overlay_Service receives a stop command, THE System SHALL terminate the overlay and stop the service
4. THE Overlay_Service SHALL maintain a foreground notification while the overlay is active

### Requirement 3: Proper Overlay Window Configuration

**User Story:** As a developer, I want to use the correct Android window type and flags, so that the overlay appears as a true system overlay over all apps.

#### Acceptance Criteria

1. THE System SHALL configure the overlay window with TYPE_APPLICATION_OVERLAY window type
2. THE System SHALL set window flags to allow interaction while preserving touch events for underlying apps
3. WHEN the overlay is displayed, THE System SHALL use WindowManager to add the overlay view at the system level
4. THE System SHALL configure the overlay layout parameters to cover the full screen while remaining draggable

### Requirement 4: Permission Verification and Handling

**User Story:** As a user, I want clear feedback when overlay permission is missing, so that I can grant the necessary permission to enable system-wide overlay functionality.

#### Acceptance Criteria

1. WHEN the user attempts to enable the floating bubble without SYSTEM_ALERT_WINDOW permission, THE System SHALL prompt the user to grant the permission
2. WHEN the permission check is performed, THE System SHALL verify Settings.canDrawOverlays() returns true before starting the overlay
3. IF SYSTEM_ALERT_WINDOW permission is not granted, THEN THE System SHALL prevent overlay service startup and display an error message
4. WHEN the user grants SYSTEM_ALERT_WINDOW permission, THE System SHALL automatically start the overlay service if the bubble is enabled

### Requirement 5: Communication Between Native Service and Flutter Overlay

**User Story:** As a developer, I want proper communication between the native Overlay_Service and the Flutter overlay isolate, so that the overlay UI can be controlled and respond to events.

#### Acceptance Criteria

1. WHEN Overlay_Service starts, THE System SHALL initialize the Flutter overlay isolate with the chatheadOverlayMain entry point
2. THE System SHALL use flutter_overlay_window plugin methods to show and hide the overlay from native code
3. WHEN the overlay needs to communicate with the native service, THE System SHALL use MethodChannel for bidirectional messaging
4. WHEN SharedPreferences flags change, THE Overlay_Isolate SHALL respond without requiring MainActivity involvement

### Requirement 6: Boot Persistence

**User Story:** As a user, I want the floating bubble to automatically restart after device reboot if it was enabled before, so that emergency functionality is always available without manual intervention.

#### Acceptance Criteria

1. WHEN the device boots and RECEIVE_BOOT_COMPLETED broadcast is received, THE BubbleBootReceiver SHALL check if the floating bubble was enabled before reboot
2. IF the floating bubble was enabled before reboot, THEN THE System SHALL start Overlay_Service automatically
3. THE System SHALL verify SYSTEM_ALERT_WINDOW permission is still granted before starting the overlay on boot
4. WHEN the overlay starts on boot, THE System SHALL restore the bubble's last known position from SharedPreferences

### Requirement 7: Lifecycle Independence from MainActivity

**User Story:** As a developer, I want the overlay lifecycle to be completely independent from MainActivity, so that the bubble works regardless of whether the main app is running.

#### Acceptance Criteria

1. WHEN MainActivity is destroyed, THE Overlay_Service SHALL continue running without interruption
2. WHEN the user force-stops the LifeGuard360 app, THE System SHALL stop the Overlay_Service
3. WHEN the overlay is active and MainActivity is started, THE System SHALL not duplicate or interfere with the existing overlay
4. THE Overlay_Service SHALL be startable without any dependency on MainActivity being active

### Requirement 8: Native Window Management

**User Story:** As a developer, I want to use native Android WindowManager to add the overlay view, so that it appears at the system level over all apps.

#### Acceptance Criteria

1. THE Overlay_Service SHALL obtain WindowManager system service to manage the overlay window
2. WHEN adding the overlay view, THE System SHALL use WindowManager.addView() with proper LayoutParams
3. THE LayoutParams SHALL specify TYPE_APPLICATION_OVERLAY, MATCH_PARENT dimensions, and appropriate flags
4. WHEN removing the overlay, THE System SHALL use WindowManager.removeView() to clean up properly

### Requirement 9: Flutter Overlay Window Plugin Integration

**User Story:** As a developer, I want to properly integrate flutter_overlay_window plugin capabilities, so that the Flutter-rendered UI appears in the system overlay window.

#### Acceptance Criteria

1. THE System SHALL use FlutterOverlayWindow.showOverlay() with appropriate parameters for system-wide display
2. WHEN showing the overlay, THE System SHALL configure overlay alignment, size, and flags for system-wide operation
3. THE System SHALL ensure the overlay entry point (chatheadOverlayMain) is correctly registered in AndroidManifest.xml
4. WHEN the overlay isolate starts, THE System SHALL initialize it with full screen dimensions (WindowSize.matchParent)

### Requirement 10: Error Handling and Graceful Degradation

**User Story:** As a user, I want clear error messages if the system-wide overlay cannot be enabled, so that I understand what went wrong and how to fix it.

#### Acceptance Criteria

1. IF WindowManager.addView() throws an exception, THEN THE System SHALL log the error and notify the user
2. IF the overlay permission is revoked while the overlay is active, THEN THE System SHALL detect the permission change and stop the service gracefully
3. WHEN the overlay service fails to start, THE System SHALL update SharedPreferences flags to reflect the failed state
4. THE System SHALL provide diagnostic logging for all overlay lifecycle events and errors
