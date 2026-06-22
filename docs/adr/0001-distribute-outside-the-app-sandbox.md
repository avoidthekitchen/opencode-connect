# Distribute outside the App Sandbox

OpenCode Connect will ship outside the Mac App Store without App Sandbox so the separately installed OpenCode process can work with user-selected projects and development tools across the filesystem. Initial distribution will prioritize source builds and clearly labeled unsigned or ad-hoc-signed GitHub artifacts; Hardened Runtime, Developer ID signing, and notarization may be added later if adoption justifies the Apple Developer account cost.

Bundling OpenCode or Tailscale and adapting arbitrary project access to App Sandbox constraints were rejected because they would substantially expand dependency, permission, and update responsibilities.
