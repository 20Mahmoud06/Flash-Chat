<p align="center">
  <img src="assets/Flash Chat.jpg" width="100%" />
</p>

<h1 align="center">⚡ Flash Chat</h1>

<p align="center">
  A full-featured real-time messaging and communication application built with Flutter.
  <br/>
  Messaging • Group Chats • Voice & Video Calls • Media Sharing • Offline Support • Security
</p>

<p align="center">
  <a href="https://drive.google.com/file/d/1JDGU0CLXgxVvMGc6h5x6wJVsq6_XCK9K/view?usp=drive_link">
    <img src="https://img.shields.io/badge/Download-APK-blue?style=for-the-badge" />
  </a>
  <img src="https://img.shields.io/badge/Flutter-3.x-blue?style=for-the-badge&logo=flutter" />
  <img src="https://img.shields.io/badge/Firebase-Backend-orange?style=for-the-badge&logo=firebase" />
  <img src="https://img.shields.io/badge/Agora-Voice%20%26%20Video-purple?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Cloudinary-Media-blue?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Platform-Android-green?style=for-the-badge&logo=android" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" />
</p>

---

## 🚀 Overview

**Flash Chat** is a full-featured real-time messaging and communication application built with **Flutter**, **Firebase**, **Agora**, and **Cloudinary**.

The project started as a simple chat application and evolved into a complete communication platform supporting private and group conversations, real-time presence, multimedia sharing, voice and video communication, push notifications, offline capabilities, and a security-focused backend architecture.

The application was developed with a strong focus on:

* ⚡ Real-time communication
* 🔐 Security
* 📱 Smooth mobile experience
* 🌐 Reliable offline/online behavior
* 📦 Efficient media and file handling
* 🎨 Modern UI/UX
* 🧩 Maintainable architecture

> **Platform:** Android

---

# ✨ Features

## 💬 Messaging

### Private Chats

* One-to-one real-time messaging
* Message delivery and read states
* Typing indicators
* Reply to messages
* Edit messages
* Delete messages
* Copy messages
* Message reactions
* Message search
* Rich message content

### 📎 Message Types

Flash Chat supports multiple types of content:

* 💬 Text messages
* 🎙️ Voice messages
* 🖼️ Images
* 🎥 Videos
* 📁 Files and documents
* 🔗 Links
* 📞 Call messages

Files and media are uploaded and delivered through dedicated media infrastructure instead of storing large binary data directly in Firestore.

---

# 👥 Group Chats

Flash Chat supports multi-participant group conversations with dedicated group management.

### Group Features

* Create groups
* Add members
* Remove members
* Leave groups
* Group name and profile image
* Group member list
* Group administrators
* Admin permissions
* Group-specific messaging
* Group message notifications
* Typing indicators
* Message reactions
* Replies, edits, deletions, and copying

---

# 📞 Voice & Video Calls

Powered by **Agora SDK**, Flash Chat supports both private and group communication.

### 🎙️ Voice Calls

* One-to-one voice calls
* Group voice calls
* Mute / unmute
* Speaker control
* Join / leave calls
* Real-time call state
* Custom incoming call ringtone
* Custom waiting / calling ringtone

### 🎥 Video Calls

* One-to-one video calls
* Group video calls
* Camera enable / disable
* Switch front/rear camera
* Mute microphone
* Speaker control
* Dynamic participant handling
* Join / leave during group calls
* Custom incoming call ringtone
* Custom waiting / calling ringtone

### 🔊 Custom Call Sounds

Flash Chat provides dedicated audio feedback for different call states:

* 📞 Custom incoming call ringtone
* 🔄 Custom waiting / calling ringtone
* 🔔 Custom notification sounds

This provides a more recognizable and consistent communication experience instead of relying entirely on the device's default sounds.

### 📞 Call Messages

Calls are integrated directly into conversations.

After a call ends, Flash Chat creates a call message containing information such as:

* Call type
* Call status
* Call duration
* Number of participants for group calls

This provides a lightweight call history directly inside the conversation without requiring a separate call-history system.

---

# 🔔 Notifications & Deep Links

Flash Chat uses Firebase Cloud Messaging for real-time notifications.

Supported notifications include:

* 💬 Private messages
* 👥 Group messages
* 📞 Incoming calls
* 🎙️ Voice calls
* 🎥 Video calls
* 📧 Email OTP verification

### 🔊 Custom Notification Sounds

Flash Chat includes custom notification audio to provide a distinct experience for app events.

Supported audio behavior includes:

* 🔔 Custom notification sound for messages and notifications
* 📞 Custom incoming call ringtone
* 🔄 Custom waiting / calling ringtone
* Different audio behavior for communication-related events

This allows important events such as messages and calls to be immediately distinguishable from standard device notifications.

Notifications are integrated with **deep linking**, allowing users to navigate directly to the relevant conversation or screen.

### 📧 Email OTP

Account verification uses a secure email-based OTP flow.

* OTP generation
* Expiration handling
* Verification flow
* Email delivery
* Deep-link integration

> SMS OTP was intentionally avoided because of its recurring third-party costs.

---

# 🟢 Online & Offline Experience

Flash Chat is designed to remain usable across changing network conditions.

### Online Presence

* Online/offline status
* Real-time presence updates
* Presence-aware conversations

### 📦 Local Caching

Frequently accessed chat data is cached locally to improve startup and browsing performance.

When the device is offline:

* Previously cached conversations remain accessible
* Available messages can still be viewed
* The app does not unnecessarily depend on a live network connection for cached content

### 🔄 Offline Message Queue

Messages created while offline can be queued locally.

Once connectivity is restored:

1. Queued messages are detected
2. Messages are synchronized with the backend
3. Delivery continues automatically

This provides a smoother experience during unstable network conditions.

---

# ⚡ Performance

Flash Chat uses several techniques to keep the application responsive as conversations grow.

* Firestore real-time updates
* Pagination for large datasets
* Local caching
* Offline message queuing
* Lazy loading
* Efficient media handling
* Feature-based project structure
* Cubit-based state management

Pagination prevents unnecessarily loading entire conversations at once, while caching reduces repeated network requests.

---

# 🌙 UI & User Experience

* Modern custom UI/UX
* Light mode
* Dark / Night mode
* Responsive conversation layouts
* Emoji-based user avatars
* Smooth messaging experience
* Media previews
* File handling UI
* Call interface
* Group management interface

The UI was designed from scratch rather than relying on a pre-built chat template.

---

# 👤 User & Privacy Features

* User profiles
* Profile editing
* Phone number integration
* Contact detection
* Block users
* Account authentication
* Password reset
* Secure email verification

### 📱 Smart Contacts

Flash Chat can detect which contacts from the user's phone are already using Flash Chat, making it easier to start conversations with existing users.

---

# 🔐 Security

Security is one of the major parts of the Flash Chat architecture.

The project includes multiple layers of protection instead of relying solely on client-side validation.

### 🛡️ Firebase Security Rules

The Firestore security rules contain extensive authorization logic covering:

* Authentication checks
* User ownership
* Conversation membership
* Group membership
* Group administrator permissions
* Message access
* Participant validation
* Protected user data
* Token-related fields
* Unauthorized document modifications

The rules form a large authorization layer rather than simply allowing authenticated users to access the database.

### 🛡️ Firebase App Check

Firebase App Check is implemented to help ensure backend resources are accessed by legitimate application instances.

This provides an additional protection layer against unauthorized clients and automated requests.

### 🔑 Secret & API Key Protection

Sensitive credentials are not committed directly to the repository.

Third-party service credentials and API secrets are protected using environment-based configuration and secure storage mechanisms.

Sensitive configuration includes services such as:

* Agora
* Cloudinary
* Other API credentials

### ☁️ Cloudflare Workflow

Instead of exposing sensitive Firebase service credentials through a client-side assets file, the project uses a **Cloudflare Workflow** for server-side processing where required.

This keeps sensitive service credentials away from the Flutter application's distributed assets.

### 🔒 Security Principles

The application follows a defense-in-depth approach:

```text
Flutter Client
      │
      ├── Secure credential handling
      │
      ├── Firebase App Check
      │
      ├── Firebase Authentication
      │
      ├── Firestore Security Rules
      │
      └── Server-side Cloudflare Workflow
                 │
                 └── Protected service credentials
```

---

# 🛠️ Tech Stack

| Technology                   | Purpose                                     |
| ---------------------------- | ------------------------------------------- |
| **Flutter**                  | Cross-platform application framework        |
| **Dart**                     | Programming language                        |
| **Firebase Authentication**  | User authentication                         |
| **Cloud Firestore**          | Real-time database                          |
| **Firebase Cloud Messaging** | Push notifications                          |
| **Firebase App Check**       | Application integrity protection            |
| **Agora SDK**                | Voice & video communication                 |
| **Cloudinary**               | Media and file storage                      |
| **Cloudflare Workflow**      | Server-side workflow / protected operations |
| **Cubit / flutter_bloc**     | State management                            |
| **Local Storage / Caching**  | Offline data and message queue              |

---

# 🏗️ Architecture Highlights

Flash Chat follows a feature-oriented Flutter architecture designed to keep the codebase scalable as functionality grows.

Major areas include:

```text
Authentication
Messaging
Groups
Calls
Notifications
Contacts
Media
Profile
Settings
Security
Offline / Caching
```

The application separates UI, state management, services, and backend-related responsibilities to make the codebase easier to maintain and extend.

---

# 📦 Installation

Clone the repository:

```bash
git clone https://github.com/20Mahmoud06/Flash-Chat.git
```

Navigate to the project:

```bash
cd Flash-Chat
```

Install dependencies:

```bash
flutter pub get
```

Run the application:

```bash
flutter run
```

---

# 🔧 Firebase Configuration

To run the project locally, configure Firebase for your own project.

Required platform configuration files:

```text
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
```

The project currently targets:

```text
Android
```

Required Firebase services include:

* Firebase Authentication
* Cloud Firestore
* Firebase Cloud Messaging
* Firebase App Check

Additional third-party services require their own configuration.

---

# 🔐 Environment Configuration

Sensitive credentials should **never** be committed to GitHub.

Examples include:

```text
Agora credentials
Cloudinary credentials
API keys
Service credentials
```

Use environment variables / secure configuration according to the project's configuration system.

---

# 📱 Download

Try the latest available Android APK:

<p align="center">
  <a href="https://drive.google.com/file/d/1cBds4V1jvY28f6EMMgnI6RQQv2GmO_OZ/view?usp=drive_link">
    <img src="https://img.shields.io/badge/Download-APK-blue?style=for-the-badge" />
  </a>
</p>

---

# 🧪 Project Highlights

Flash Chat was developed and continuously improved over several months, evolving from a basic messaging prototype into a much more complete communication application.

### Major areas implemented from scratch

* Real-time private messaging
* Group conversations
* Group administration
* Voice messaging
* Image/video sharing
* File sharing
* Link messages
* Voice calls
* Video calls
* Group calls
* Online presence
* Push notifications
* Deep linking
* Email OTP verification
* Offline caching
* Offline message synchronization
* Pagination
* User blocking
* Contact detection
* Dark mode
* Firebase authorization rules
* App Check
* Secure API configuration
* Cloudflare server-side workflows

---

# 🤝 Contributing

Contributions, feature requests, bug reports, and improvements are welcome.

To contribute:

```bash
git fork https://github.com/20Mahmoud06/Flash-Chat.git
```

Create a feature branch, make your changes, and submit a pull request.

---

# 📜 License

This project is licensed under the MIT License.

---

# 👨‍💻 Developer

### Mahmoud Safa

Flutter Developer focused on building real-world mobile applications with modern UI/UX, scalable architecture, real-time systems, and security-conscious backend integration.

<p align="center">
  <a href="https://github.com/20Mahmoud06">
    GitHub
  </a>
  &nbsp;•&nbsp;
  <a href="https://www.linkedin.com/in/20mahmoud-safa06/">
    LinkedIn
  </a>
  &nbsp;•&nbsp;
  <a href="https://20mahmoud06.github.io/My-Portfolio/">
    Portfolio
  </a>
</p>

---

<p align="center">
  Built with ❤️ and Flutter by <strong>Mahmoud Safa</strong>
</p>
