import type { ReactNode } from "react";
import { REPO, AUTHOR, AUTHOR_URL } from "../site";

export type LegalSection = { heading: string; body: ReactNode };
export type LegalDoc = {
  title: string;
  updated: string;
  intro: ReactNode;
  sections: LegalSection[];
};

const A = ({ href, children }: { href: string; children: ReactNode }) => (
  <a href={href} className="text-[var(--color-accent-bright)] underline-offset-2 hover:underline">
    {children}
  </a>
);

const UPDATED = "June 18, 2026";

export const privacyDoc: LegalDoc = {
  title: "Privacy Policy",
  updated: UPDATED,
  intro: (
    <>
      Crisp is a native macOS app from {AUTHOR} that removes pauses and filler words from your
      recordings. It is built to be private by default: <strong className="text-white">everything
      happens on your Mac.</strong> We don’t run servers that receive your data, we have no
      accounts, and we never see your recordings.
    </>
  ),
  sections: [
    {
      heading: "The short version",
      body: (
        <p>
          We don’t collect, transmit, sell, or store your personal data or your video files. There
          is no analytics, no telemetry, no advertising, and no third-party tracking in the app.
          Your footage never leaves your computer.
        </p>
      ),
    },
    {
      heading: "What Crisp does on your device",
      body: (
        <>
          <p>
            When you clean a video, every step runs locally on your Mac: detecting silence from the
            audio, transcribing filler words with an on-device speech model, and re-rendering the
            cut. Crisp only ever writes a new <code className="rounded bg-white/10 px-1 py-0.5 font-mono text-[13px]">…_cleaned</code> file
            and backs up your original first — it never modifies or deletes your source, and none of
            this involves the network.
          </p>
        </>
      ),
    },
    {
      heading: "When Crisp uses the network",
      body: (
        <>
          <p>For full transparency, these are the only times the app reaches the internet:</p>
          <ul className="mt-3 list-disc space-y-2 pl-5">
            <li>
              <strong className="text-white">First-run model download.</strong> The first time you
              remove filler words, Crisp downloads a speech model (~148&nbsp;MB) once from{" "}
              <A href="https://huggingface.co/ggerganov/whisper.cpp">Hugging Face</A>. This is a
              plain file download — no personal data is sent. That request is subject to Hugging
              Face’s privacy policy.
            </li>
            <li>
              <strong className="text-white">Update checks.</strong> Stable and Nightly builds ask
              the <A href="https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement">GitHub</A>{" "}
              API whether a newer version exists, and download it if you choose to update. GitHub may
              log standard request metadata (such as your IP address) per its own policy.
            </li>
            <li>
              <strong className="text-white">Installation via Homebrew.</strong> If you install with
              Homebrew, the download comes from GitHub Releases and is handled by Homebrew and GitHub.
            </li>
          </ul>
          <p className="mt-3">
            That’s the complete list. There is no analytics, telemetry, crash reporting, or any
            third-party SDK bundled with Crisp.
          </p>
        </>
      ),
    },
    {
      heading: "Information we collect",
      body: (
        <p>
          None. We operate no servers that receive your data and we have no account system, so there
          is nothing for us to collect, profile, or share.
        </p>
      ),
    },
    {
      heading: "This website",
      body: (
        <p>
          This site is a static marketing page. It sets no cookies and runs no analytics or tracking
          scripts. Whoever hosts the site may keep standard server access logs (for example IP
          address and user agent) for security and operations, under their own policy. Links out to
          GitHub, Hugging Face, brew.sh, and {AUTHOR_URL.replace("https://", "")} are governed by
          those sites’ policies.
        </p>
      ),
    },
    {
      heading: "Your control",
      body: (
        <p>
          You can delete the downloaded model, ignore updates, or remove Crisp entirely with{" "}
          <code className="rounded bg-white/10 px-1 py-0.5 font-mono text-[13px]">brew uninstall --zap --cask crisp</code>,
          which also clears Crisp’s local data and settings from your Mac.
        </p>
      ),
    },
    {
      heading: "Children",
      body: (
        <p>
          Crisp is not directed to children under 13, and in any case the app collects no personal
          information from anyone.
        </p>
      ),
    },
    {
      heading: "Open source",
      body: (
        <p>
          Crisp is open source under the GPL-3.0 license. You don’t have to take our word for any of
          this — you can read exactly what the app does in{" "}
          <A href={REPO}>the source code</A>.
        </p>
      ),
    },
    {
      heading: "Changes & contact",
      body: (
        <p>
          If this policy changes, we’ll update this page and the date above. Questions? Reach us via{" "}
          <A href={REPO}>the GitHub repository</A> or <A href={AUTHOR_URL}>{AUTHOR_URL.replace("https://", "")}</A>.
        </p>
      ),
    },
  ],
};

export const termsDoc: LegalDoc = {
  title: "Terms of Use",
  updated: UPDATED,
  intro: (
    <>
      These terms cover your use of the Crisp app and this website, both provided by {AUTHOR}. Crisp
      is free, open-source software — the plain-language terms below sit alongside the GPL-3.0
      license that legally governs the code.
    </>
  ),
  sections: [
    {
      heading: "Acceptance",
      body: <p>By downloading, installing, or using Crisp, or by using this website, you agree to these terms. If you don’t agree, please don’t use them.</p>,
    },
    {
      heading: "License",
      body: (
        <p>
          Crisp is free and open-source software licensed under the{" "}
          <A href={`${REPO}/blob/main/LICENSE`}>GNU General Public License v3.0</A>. You may use,
          study, modify, and redistribute it under the terms of that license, which take precedence
          for anything concerning the source code.
        </p>
      ),
    },
    {
      heading: "No warranty",
      body: (
        <p>
          Crisp is provided <strong className="text-white">“as is,” without warranty of any kind</strong>,
          express or implied, including merchantability or fitness for a particular purpose, as set
          out in the GPL-3.0. You use it at your own risk.
        </p>
      ),
    },
    {
      heading: "Limitation of liability",
      body: (
        <p>
          To the maximum extent permitted by law, {AUTHOR} and the authors are not liable for any
          damages arising from your use of Crisp. Although Crisp is designed never to modify or
          delete your original files and to back them up first, software can fail — keep your own
          backups of anything important.
        </p>
      ),
    },
    {
      heading: "Third-party components",
      body: (
        <p>
          Crisp drives bundled open-source tools — including <A href="https://ffmpeg.org">FFmpeg</A>,{" "}
          <A href="https://github.com/ggerganov/whisper.cpp">whisper.cpp</A>, a Python runtime, and a
          speech model — each under its own license. Your use of Crisp is also subject to those
          licenses.
        </p>
      ),
    },
    {
      heading: "Acceptable use",
      body: <p>Use Crisp only on recordings you own or have the right to edit. You are solely responsible for the content you process and for how you use the results.</p>,
    },
    {
      heading: "Trademarks & branding",
      body: (
        <p>
          The “Crisp” name, logo, icon, and the content of this website are © {AUTHOR}. The GPL-3.0
          applies to the source code, not to the project’s name or branding.
        </p>
      ),
    },
    {
      heading: "The website",
      body: <p>This website is provided for information on an “as is” basis. We may change, update, or discontinue any part of it at any time without notice.</p>,
    },
    {
      heading: "Changes to these terms",
      body: <p>We may update these terms from time to time. Material changes will be reflected here with a new date above; continued use means you accept the updated terms.</p>,
    },
    {
      heading: "Governing law & contact",
      body: (
        <p>
          These terms are governed by the laws of the jurisdiction in which {AUTHOR} operates,
          without regard to conflict-of-law rules. Questions? Reach us via{" "}
          <A href={REPO}>the GitHub repository</A> or <A href={AUTHOR_URL}>{AUTHOR_URL.replace("https://", "")}</A>.
        </p>
      ),
    },
  ],
};
