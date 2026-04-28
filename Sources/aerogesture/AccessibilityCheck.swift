import ApplicationServices

func checkAccessibilityPermissions() {
    guard AXIsProcessTrusted() else {
        fputs("""
        aerogesture: Accessibility access is required.

        Grant access in:
          System Settings > Privacy & Security > Accessibility

        Add this binary to the list, then re-run aerogesture.

        """, stderr)
        exit(1)
    }
}
