# LogYourBody iOS Project Structure

## Xcode Organization Guide

When organizing in Xcode, create the following group structure:

```
LogYourBody/
├── App/
│   ├── LogYourBodyApp.swift
│   └── Info.plist
├── Core/
│   ├── Models/
│   │   ├── User.swift
│   │   └── WeightEntry.swift
│   ├── Services/
│   │   └── AuthManager.swift
│   └── Utils/
│       └── Constants.swift
├── Features/
│   ├── Authentication/
│   │   ├── LoginView.swift
│   │   └── SignUpView.swift
│   ├── Dashboard/
│   │   └── DashboardView.swift
│   ├── Weight/
│   │   └── LogWeightView.swift
│   ├── Photos/
│   │   └── PhotosView.swift
│   └── Settings/
│       └── SettingsView.swift
├── Shared/
│   ├── Views/
│   │   ├── ContentView.swift
│   │   └── MainTabView.swift
│   └── Extensions/
│       ├── Color+Theme.swift
│       └── Font+Custom.swift
├── Resources/
│   ├── Assets.xcassets/
│   └── Preview Content/
└── ViewModels/
    └── (future view models)
```

## How to Organize in Xcode:

1. **Delete existing groups** (right-click → Delete → Remove Reference)
2. **Create new groups** (right-click → New Group)
3. **Drag files** into appropriate groups
4. **Set folder references** to match physical structure

## Color Scheme Applied:
- Background: #0A0B0D (Linear dark)
- Cards: #111113
- Primary: #5E6AD2 (Purple)
- Text: #F7F8F8
- Secondary Text: #9CA0A8

## Typography:
- Using system fonts matching Inter
- Monospace for numbers
- Consistent sizing with web app