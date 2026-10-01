# Why macOS asks you to confirm before opening Film Grain

[Version française →](macos-security.fr.md) · [← Back to the README](../README.md)

**The short version.** macOS warns about any app that is not from the App
Store and is not **signed with an Apple Developer ID** and **checked by Apple**
(that check is called *notarisation*). Film Grain is neither, so macOS cannot
tell who made it or whether Apple has looked at it. **That is all the warning
says.** It is not a verdict on what the app does.

It is also, honestly, a good reason not to simply take my word for it. So this
page explains what is going on, and then shows you three ways to check for
yourself, or to avoid the warning altogether.

---

## What is going on

When you download a file with a browser, macOS marks it *"downloaded from the
internet"* (a hidden flag called **quarantine**). The first time you open a
marked app, a built-in check named **Gatekeeper** looks for two things:

1. **A signature from an Apple Developer ID.** Apple issues that certificate to
   registered developers (the Apple Developer Program, currently about 99 US
   dollars a year). It says: *"this app was made by this developer, and has not been
   changed since."*
2. **Notarisation.** The developer uploads the app to Apple, which scans it
   automatically for known malware and records that it passed.

Film Grain has **neither**. This project does not use a Developer ID.

What it does have is an **"ad hoc" signature**: a signature with no identity
behind it. Apple Silicon Macs require *some* signature before they run any
code, so the build adds this one — but it proves nothing about the author. You
can see this on your own copy:

```
codesign -dv --verbose=2 "/Applications/Film Grain.app" 2>&1 | grep -E "Signature|TeamIdentifier"
```

It prints `Signature=adhoc` and `TeamIdentifier=not set`. And Gatekeeper's own
verdict:

```
spctl --assess --type execute -vv "/Applications/Film Grain.app"
```

says `rejected` — which, for a downloaded app, is simply how Gatekeeper says
*"I cannot vouch for this one."* (An app you build yourself is never marked as
downloaded, so macOS never asks about it. See option 3 below.)

## So is it safe?

The warning cannot tell you, and its absence on other apps does not tell you
either. What you can do instead of trusting me:

- **Read the source.** It is all in [`source/`](../source): about 1,000 lines of
  Swift in three files, plus the build script. There is **no network code** in
  it (the app never connects to anything), it **starts no other program**, and
  it uses **no third-party code** — only what macOS itself provides.
- **Check that your download is the file that was published.** The release
  notes give its SHA-256 fingerprint. After downloading, in Terminal:

  ```
  shasum -a 256 ~/Downloads/Film-Grain-0.3-macos-arm64.zip
  ```

  The two must match.
- **Build it yourself** — see option 3.

## Three ways to go on

### 1. Open it anyway (once)

**On macOS 15 (Sequoia) and later, including macOS 26:**

1. Double-click *Film Grain*. A message says Apple could not verify that it is
   free of malware. Click **Done** — *not* "Move to Trash".
2. Open **System Settings → Privacy & Security** and scroll down to the
   **Security** section. It says *"Film Grain" was blocked to protect your
   Mac*, with an **Open Anyway** button. Click it and confirm with your
   password or Touch ID.
3. macOS asks one last time. Click **Open**.

After that it opens normally, every time.

**On macOS 14 (Sonoma):** right-click (or Control-click) *Film Grain*, choose
**Open**, then **Open** again.

> The exact wording of these messages changes a little between macOS versions
> and languages. The path — System Settings → Privacy & Security → Open
> Anyway — is the one Apple documents.

### 2. Remove the "downloaded" flag yourself

If you are comfortable in Terminal, this deletes the quarantine flag, and macOS
stops asking. Adjust the path to wherever you put the app:

```
xattr -dr com.apple.quarantine "/Applications/Film Grain.app"
```

Only do this for an app whose source you have looked at or whose author you
trust — it switches off the very check this page is about.

### 3. Build it yourself — no warning at all

An app you build on your own Mac was never downloaded, so it is never marked,
and macOS has nothing to ask. You need Apple's command line tools (not the full
Xcode), then three commands — they are in the
[README](../README.md#-get-it--two-ways). It takes a few seconds, and as a
bonus you have read what you are running.

---

## Why not just sign it properly?

Because it would mean enrolling in Apple's paid developer program and
submitting every release to Apple, for a small free tool. If that changes, this
page will say so. Until then: the source is here, the fingerprint is in the
release notes, and building it yourself is always an option.
