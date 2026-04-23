# CloudMounter 1.0.0

## 🎉 Initial Release

CloudMounter is a professional macOS application for mounting and managing cloud storage directly in your file system.

### ✨ Features

- **Multi-Cloud Support**: Connect to 10+ cloud providers
  - OneDrive, Google Drive, Dropbox, Amazon S3
  - SFTP, Box, MEGA, Backblaze B2, Azure Blob Storage
  - Generic rclone-compatible providers

- **Account Management**
  - Add and manage multiple cloud accounts
  - Automatic mount point configuration
  - Persistent storage with recovery

- **Space Monitoring**
  - Real-time cloud storage usage (used/total)
  - Local cache size tracking
  - Visual progress bars for quick status

- **Professional macOS UI**
  - Native SwiftUI interface
  - System notifications
  - Light/Dark mode support
  - Seamless Finder integration

### 🚀 Installation

1. Download `CloudMounter-1.0.0.dmg`
2. Open the DMG file
3. Drag `CloudMounter.app` to the `Applications` folder
4. Launch from Applications or Launchpad

### 📋 Requirements

- macOS 13.0 or later
- rclone installed (install via Homebrew: `brew install rclone`)
- Cloud storage account(s) with rclone configuration

### 🔧 Configuration

CloudMounter uses your existing rclone configuration. Configure remotes with:
```bash
rclone config
```

### 📚 Documentation

- **README.md** - Complete documentation and usage guide
- **QUICKSTART.md** - Quick start guide for new users

### 🐛 Known Limitations

- Requires rclone installation and configuration
- Mount points are read-write depending on rclone backend permissions
- Some cloud providers may have rate limits on API calls

### 📄 License

CloudMounter is provided as-is. See included documentation for details.

---

**Built with Swift and SwiftUI on macOS**
