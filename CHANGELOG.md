# CloudMounter Changelog

## [1.2.0] - 2026-04-23

### New Features

#### 📊 Enhanced Progress Monitoring
- **Larger Progress Bar**: 44pt height with gradient (blue → cyan)
- **Percentage Display**: Large, bold percentage text centered on progress bar
- **Visual Feedback**: Blue-tinted progress panel with detailed statistics
- **Real-time Stats**: 
  - Current/total bytes transferred (monospaced font)
  - Instant speed in MB/s
  - Elapsed time and ETA in clear layout
  - All metrics update every second

#### 📦 Move Operation (Safe File Relocation)
- **Three Transfer Types**:
  - **Copy** (📋): Copies files, keeps originals (safest)
  - **Sync** (🔄): Mirrors source to destination (destructive, use carefully)
  - **Move** (📦): Copies first, then deletes originals (safe relocation)
- **Operation Descriptions**: Visual callout explains each option
- **Move Workflow**:
  1. Executes rclone copy (transferencia)
  2. On success, executes rclone delete of source
  3. Fails safely if delete encounters errors
- **Better UI**: Menu picker replaces segmented control (fits 3 options better)

### Improvements

- Progress bar much more visible (44pt height, gradient colors)
- Percentage progress easier to read
- Operation selection clearer with descriptions
- Move operation adds safety for file relocation
- Better statistics layout for monitoring transfers
- Visual indication of operation type (color-coded labels)

### Bug Fixes

- Fixed Swift actor isolation warnings in transfer completion logic
- Proper concurrent code handling for move operations

## [1.1.1] - 2026-04-23

### New Features

#### 📁 Folder Explorer for Transfers
- **Browse Button**: Click folder icon next to each path field to visually select folders
- **Native File Picker**: Uses macOS NSOpenPanel for intuitive folder selection
- **Auto Mount Point Detection**: Opens directly in the selected remote's mount point
- **Relative Path Conversion**: Automatically converts absolute paths to relative paths
- **Root Selection**: Selecting the mount root clears the folder field (copies from root)

### Improvements

- Easier folder selection (no need to type paths)
- Better user experience with visual folder browser
- Automatic path normalization
- Graceful handling of mounted vs unmounted remotes

## [1.1.0] - 2026-04-23

### New Features

#### 🚀 Integrated Transfer Tool
- **New Transfers Tab**: Dedicated interface for copying/syncing files between cloud remotes
- **Folder Selection**: Choose specific source and destination folders (not just root)
- **Real-time Progress**: Monitor transfer with live progress bar, speed (MB/s), and ETA
- **Transfer Types**: 
  - Copy: Safe, doesn't delete destination files
  - Sync: Mirrors source to destination (destructive)
- **Transfer History**: View last 5 completed transfers with status, duration, and stats
- **Cancel Anytime**: Stop transfers mid-process with cancel button

#### ⚙️ Configurable Mount Parameters
- **Advanced Settings Section** in Settings tab
- **Customizable Parameters**:
  - Cache mode: off, minimal, writes, full
  - Cache size: 1-20 GB
  - Buffer size: 16-256 MB
  - Concurrent transfers: 1-16
  - Connection timeout: 5-120 minutes
  - Retry count and delay
  - Low-level retries and cache read retries
- **Quick Presets**:
  - Balanced (default): Good mix of speed and reliability
  - Fast (aggressive): Maximum concurrent transfers and large cache
  - Stable (conservative): Minimal transfers, smaller cache, more retries

### Improvements

- **Dynamic Mount Arguments**: Mount parameters now read from TransferConfig instead of hardcoded values
- **Better Path Handling**: Correct handling of folder paths in transfers (with/without leading slash)
- **Enhanced Persistence**: Transfer config and history saved to UserDefaults
- **UI Polish**: Better spacing and organization in Transferencias tab

### Technical Changes

- Added `TransferConfig` struct with 10+ configurable parameters
- Extended `AccountStore` with transfer config and history management
- Implemented `TransferJob` class with status tracking and progress calculations
- Added transfer functions to `RcloneService`: `startTransfer()`, `cancelTransfer()`
- Improved `buildMountArgs()` to read dynamic configuration
- Enhanced error handling for transfer failures
- Regex-based stats parsing from rclone output

### Bug Fixes

- Fixed mount detection for /tmp symlink paths (now uses `df` instead of `mount`)
- Corrected Google Drive mount arguments (removed incorrect value for boolean flags)
- Proper path construction for folder transfers

### Files Modified

- `Sources/CloudMounter/Models/Models.swift`: Added TransferConfig, TransferStatus, TransferJob
- `Sources/CloudMounter/Models/AccountStore.swift`: Added config and history persistence
- `Sources/CloudMounter/Services/RcloneService.swift`: Added transfer functions, dynamic params
- `Sources/CloudMounter/Views/ContentView.swift`: Added Transfers tab
- `Sources/CloudMounter/Views/Views.swift`: Added AdvancedTransferSettings, TransferView

## [1.0.0] - 2026-04-22

### Initial Release

#### Core Features
- Multi-provider cloud storage mounting (OneDrive, Google Drive, Dropbox, etc.)
- OAuth-based authentication
- Automatic mount on startup
- FUSE and WebDAV support
- Space usage visualization
- Cache management
- Dependency verification
- Logging interface

#### Technical Foundation
- Swift-based native macOS application
- SwiftUI interface
- rclone integration
- Account persistence
- Real-time mount status tracking

---

## Upgrade Instructions

### From 1.0.0 to 1.1.0

1. **Close CloudMounter** if running
2. **Download** CloudMounter-1.1.0.dmg
3. **Drag** CloudMounter.app to Applications
4. **Re-open** from Applications

Your existing accounts and settings will be preserved. New options will use sensible defaults.

### Settings Migration

- Old mount parameters are replaced with new configurable defaults
- Transfer history starts fresh
- No data loss, only parameter format changes

---

## Known Issues

- None at this time

## Future Plans (v1.2.0)

- [ ] Background transfer daemon (persist across app restart)
- [ ] Scheduled transfers (daily, weekly)
- [ ] Transfer templates for common patterns
- [ ] Bandwidth throttling
- [ ] Pre-transfer hash verification
- [ ] Transfer completion notifications

