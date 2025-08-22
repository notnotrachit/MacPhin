# Mac File Explorer

A Windows File Explorer-like application for macOS built with SwiftUI.

## Features

- **Multiple View Modes**: List, Icons, and Columns view (similar to Windows Explorer)
- **Sidebar Navigation**: Quick access to common folders (Home, Desktop, Documents, Downloads, etc.)
- **Full Keyboard Navigation**: Complete keyboard control with arrow keys, shortcuts, and focus management
- **File Operations**: 
  - Open files with default applications
  - Create new folders
  - Move files to trash
  - Copy/Cut/Paste files
  - Duplicate files
  - Show file info
- **Navigation**: 
  - Back/Forward navigation history
  - Up directory navigation
  - Breadcrumb address bar (clickable path components)
- **Sorting**: Sort by name, size, date modified, or file type
- **Search**: Search for files and folders within the current directory
- **Context Menus**: Right-click context menus with file operations
- **File Selection**: Single and multiple file selection with keyboard support
- **Hidden Files**: Toggle visibility of hidden files
- **Tabbed Interface**: Multiple tabs for efficient file management

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Building and Running

1. Clone or download the project
2. Open Terminal and navigate to the project directory
3. Run the application:

```bash
swift run
```

Or build the project:

```bash
swift build
```

## Project Structure

```
Sources/MacFileExplorer/
├── main.swift                    # App entry point
├── ContentView.swift             # Main app layout
├── FileExplorerManager.swift     # Core file management logic
├── Models/
│   └── FileItem.swift           # File and folder data models
└── Views/
    ├── SidebarView.swift        # Left sidebar with favorites
    ├── FileExplorerView.swift   # Main file browser view
    ├── FileListView.swift       # List view mode
    ├── FileIconView.swift       # Icon view mode
    ├── FileColumnView.swift     # Column view mode
    ├── FileContextMenu.swift    # Right-click context menu
    └── SearchView.swift         # File search functionality
```

## Usage

### Navigation
- Use the sidebar to quickly navigate to common folders
- Click on path components in the address bar to navigate up the hierarchy
- Use the Back/Forward buttons in the toolbar
- Double-click folders to enter them

### View Modes
- **List View**: Detailed file information in a table format
- **Icon View**: Large icons in a grid layout
- **Column View**: Multi-column browser with file preview

### File Operations
- Double-click files to open them with the default application
- Right-click for context menu with file operations
- Select multiple files using Cmd+click
- Create new folders using the context menu

### Sorting
- Click column headers in List view to sort
- Use the Sort menu in the toolbar or context menu
- Toggle between ascending and descending order

### Search
- Use Cmd+F or the search functionality to find files
- Search is performed recursively in the current directory

### Keyboard Navigation
The file manager is fully navigable using keyboard shortcuts:

#### Navigation
- **↑/↓ Arrow Keys**: Move selection up/down in file list
- **←/→ Arrow Keys**: Switch between sidebar and file list
- **Enter**: Open selected item
- **Space**: Toggle selection of current item
- **Shift + ↑/↓**: Extend selection
- **Tab**: Move focus between UI elements
- **Shift + Tab**: Move focus backwards
- **Escape**: Clear selection

#### File Operations
- **⌘ + C**: Copy selected items
- **⌘ + X**: Cut selected items  
- **⌘ + V**: Paste items
- **⌘ + A**: Select all items
- **⌘ + N**: Create new folder
- **⌘ + D**: Duplicate selected items
- **Delete**: Move selected items to trash

#### View Controls
- **⌘ + 1**: Switch to List view
- **⌘ + 2**: Switch to Icon view
- **⌘ + 3**: Switch to Column view
- **⌘ + R**: Refresh current folder
- **⌘ + Shift + H**: Toggle hidden files

#### Navigation Shortcuts
- **⌘ + ↑**: Go to parent folder
- **⌘ + ←**: Go back in history
- **⌘ + →**: Go forward in history

#### Search
- **⌘ + F**: Open/close search
- **⌘ + Shift + F**: Global search

#### Tab Management
- **⌘ + T**: New tab
- **⌘ + W**: Close current tab
- **⌘ + 1-9**: Switch to tab by number

#### Quick Actions
- **⌘ + Shift + C**: Copy file path to clipboard
- **⌘ + Shift + R**: Reveal in Finder
- **⌘ + ?**: Show keyboard shortcuts help

## Customization

The application can be easily customized by modifying:

- **File Icons**: Update the `icon` and `iconColor` properties in `FileItem.swift`
- **Sidebar Items**: Modify the `SidebarItem` enum to add/remove sidebar entries
- **View Modes**: Extend the view mode system by adding new cases to `ViewMode`
- **File Operations**: Add new operations in `FileContextMenu.swift`

## Known Limitations

- Search is currently limited to filename matching (not content search)
- No file preview for media files (images, videos)
- No network drive support in the sidebar
- Limited file operation feedback (no progress indicators for long operations)

## Future Enhancements

- File preview panel with image/document previews
- Content-based search
- Network location support
- File operation progress indicators
- Enhanced drag and drop support
- Customizable toolbar
- File tags and labels support
- Quick Look integration
- Advanced search filters

## License

This project is open source and available under the MIT License.