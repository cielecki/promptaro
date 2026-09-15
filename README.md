# Promptaro

Your saved prompts, right above the chat input.

[Website](https://promptaro.cielecki.com/) · [Download](https://github.com/cielecki/promptaro/releases/latest)

Promptaro is a small macOS menu bar app. It shows a row of editable prompt buttons
above the focused chat composer. Click a button to insert its full text and send.

## Install

Requires macOS 14 or later. The release app includes Apple Silicon and Intel builds
and is signed and notarized. Intel runtime testing is still pending.

1. Download `Promptaro-1.0.0-macOS.zip` from this repository's Releases page.
2. Unzip it and move **Promptaro.app** to **Applications**.
3. Open Promptaro and enable it in **System Settings → Privacy & Security → Accessibility**.
4. Focus a chat input. Your prompt buttons appear above it.

If permission remains unavailable, quit and reopen Promptaro. When replacing an
older development build, you may need to remove its Accessibility entry and add
the installed app again.

## Make it yours

Click the pencil on the palette or **Edit Prompts…** in the menu bar menu. Each
prompt has a short button label and full text, including multiple paragraphs.
Drag rows or use the up/down buttons to reorder them. Click **Save prompts** to
apply changes. **Preview buttons** lets you try the layout without sending.

The seven defaults are Next step?, Proceed, Step back, Explain, TLDR, Reorient,
and Wrap up. All are editable. Defaults apply only when no saved configuration
exists, so an update preserves your prompts.

Click **×** to dismiss the palette until focus leaves the input. Use **Pause** to
hide it, or **Launch at Login** to start it automatically. Startup is off by default.

## Sending and privacy

A click pastes at the cursor, replacing selected text. Existing draft text is
otherwise retained and will be sent too. Promptaro checks that insertion is visible
through macOS Accessibility before pressing Return once. If focus changes or
Promptaro cannot verify the paste, it does not press Return.
The destination must use Return to send.

The app has no account, model API, analytics, or background network requests.
Prompts stay in `~/Library/Application Support/Prompt Palette/prompts.json`; the
older folder name preserves existing installations. Clipboard contents are restored
after insertion unless something newer has been copied in the meantime.

Accessibility permission lets Promptaro locate and read the focused composer and
send paste/Return keystrokes. Clicking a prompt submits it to the chat service you
are using, under that service's own privacy terms.

## Compatibility

Detection is implemented for ChatGPT, Codex, Claude Desktop (including its Code
view), and OpenCode Desktop. Browser detection uses macOS Accessibility without
an extension or a website allowlist. Safari, Chrome, and other browsers need to
expose an editable composer and page URL.

Early testing includes user-confirmed multiline sending in ChatGPT on desktop
and in Chrome, plus appearance and placement in Safari and Claude Code desktop.
This is not a guarantee for every app version. Safari sending, OpenCode Desktop,
other browsers, installation by a new user, and Intel runtime still need wider testing.

Browser detection can also show buttons in other multiline web forms. Custom
editors may expose too little information for insertion verification or accurate
placement. Search and password fields are excluded. Terminal windows and CLI
chat apps are unsupported.

Slack's desktop app and Slack web pages are excluded.

## Build

Requires macOS 14+ and Swift 6 / Xcode command line tools. There are no third-party
Swift package dependencies.

```sh
swift test
PROMPT_PALETTE_SIGNING_IDENTITY=- ./scripts/build.sh
```

This creates `dist/Promptaro.app` for the host architecture with a temporary ad-hoc
signature. A changed ad-hoc binary may require refreshing Accessibility permission.
Use your own Apple Development identity through `PROMPT_PALETTE_SIGNING_IDENTITY`
for a stable development signing identity.

For a universal distribution build, set `PROMPT_PALETTE_DISTRIBUTION_IDENTITY` to
your Developer ID Application identity and run `./scripts/build.sh --distribution`.
To notarize and staple, configure your own `notarytool` Keychain profile, then run:

```sh
PROMPT_PALETTE_NOTARY_PROFILE=your-profile ./scripts/release.sh
```

The release script requires successful notarization, stapling, and Gatekeeper
assessment before creating the final ZIP and SHA-256 checksum.

The bundle ID, executable name, and settings folder keep their original names
for compatibility with existing installations.

## Contributing

Report bugs with your macOS version, target app/browser version, and steps to
reproduce. Remove private chat content from screenshots. For code changes, run
`swift test` and keep changes focused. Never test automatic sending in someone
else's existing conversation.

## License

MIT. See [LICENSE](LICENSE).
