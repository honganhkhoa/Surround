[![CI](https://github.com/honganhkhoa/Surround/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/honganhkhoa/Surround/actions/workflows/main.yml)

<h1 align="center">
  <img src="https://files.honganhkhoa.com/surround/appicon.png" width="120" height="120" style="border-radius:20px;"><br />
  <a href="https://apps.apple.com/app/id1535010544"><img src="https://files.honganhkhoa.com/surround/appstore.png" height="60"></a>
</h1>

# Surround

This repository contains the client code for Surround, an iOS app to play Go online on the [Online-Go.com](https://online-go.com) server (Online Go Server - OGS). The app aims to provide the best OGS experience on iOS devices.

![Surround App Screenshots](https://files.honganhkhoa.com/surround/screenshots.png)

---

# About
Surround is a fairly complex application built entirely in Swift, with the UI built mostly in SwiftUI. The project heavily uses SwiftUI previews with a lot of sample data, so I can work on the design using the same tool I use to code the app (Xcode).

I made this project open source with a permissive license in the hope that it can help improving the quality of Go apps in general. If you are working on some Go related app, I hope you can find something useful here.

# Getting Started
1. It is quite straightforward to run this project, just open the Xcode project file (`Surround.xcodeproj`) with a not-too-old version of Xcode, and you should be able to build and run the project.
2. You might have a warning on missing a "pc file". That is a [known issue](https://github.com/daltoniam/Starscream/issues/719) caused by the [Starscream](https://github.com/daltoniam/Starscream) library, which is a dependency of the [Socket.io client library for Swift](https://github.com/socketio/socket.io-client-swift). You can ignore the warning or install `pkg-config` as instructed in the issue link to silence the warning.
3. To use the beta site of OGS, change the `ogsRoot` variable in the `OGSService.swift` file to the URL of OGS's beta site (https://beta.online-go.com).

### About Surround on macOS
Surround can run as a macOS app without any modification, just set Xcode to build and run for macOS and it should work pretty well. However, I have not done any work to optimize the app for macOS so it is pretty rough, might contains a lot of bugs.

Currently I don't have plan to work on the macOS part. If you want to use this project as a base to create your own macOS client for OGS, feel free to do so as long as you follow the terms in the license.

# Contact
- Send me a message on either [OGS](https://online-go.com/player/314459/) or the [OGS Forums](https://forums.online-go.com/u/honganhkhoa/summary).
- [OGS Forums thread for Surround](https://forums.online-go.com/t/surround-ios-client-for-ogs/34437).
- Send me an email: khoahong@hey.com

# License
This project is released under the BSD 3-Clause license. See [LICENSE](LICENSE) for details.
