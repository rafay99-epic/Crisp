import type { ReactNode } from "react";
import { REPO, AUTHOR, AUTHOR_URL, CONTACT_EMAIL, JURISDICTION } from "../site";

const Email = () => (
  <a href={`mailto:${CONTACT_EMAIL}`} className="text-[var(--color-accent-bright)] underline-offset-2 hover:underline">
    {CONTACT_EMAIL}
  </a>
);
const contactLine = (
  <>
    email us at <Email /> or open an issue on{" "}
    <a href={REPO} className="text-[var(--color-accent-bright)] underline-offset-2 hover:underline">
      the GitHub repository
    </a>
  </>
);

export type LegalSection = { heading: string; body: ReactNode };
export type LegalDoc = {
  title: string;
  updated: string;
  intro: ReactNode;
  note: ReactNode; // small "not legal advice / transparency" line under the intro
  sections: LegalSection[];
};

const A = ({ href, children }: { href: string; children: ReactNode }) => (
  <a href={href} className="text-[var(--color-accent-bright)] underline-offset-2 hover:underline">
    {children}
  </a>
);
const Caps = ({ children }: { children: ReactNode }) => (
  <strong className="font-semibold text-white">{children}</strong>
);
const code = "rounded bg-white/10 px-1 py-0.5 font-mono text-[13px]";

const UPDATED = "June 18, 2026";
const NOT_ADVICE = (
  <>
    This document is provided for transparency and your convenience. It is not legal advice and does
    not create an attorney–client relationship.
  </>
);

export const privacyDoc: LegalDoc = {
  title: "Privacy Policy",
  updated: UPDATED,
  note: NOT_ADVICE,
  intro: (
    <>
      Crisp is a native macOS app from {AUTHOR} (“we,” “us”) that removes pauses and filler words from
      your recordings. It is built to be private by default: <Caps>everything happens on your Mac.</Caps>{" "}
      We operate no servers that receive your data, we have no user accounts, and we never see your
      recordings. This policy explains, plainly and completely, what does and doesn’t happen.
    </>
  ),
  sections: [
    {
      heading: "1. The short version",
      body: (
        <p>
          We do not collect, transmit, sell, rent, or store your personal information or your video
          files. Crisp contains no analytics, no telemetry, no advertising, and no third-party
          tracking. Your footage never leaves your computer as a result of using Crisp.
        </p>
      ),
    },
    {
      heading: "2. What Crisp does on your device",
      body: (
        <p>
          When you clean a video, every step runs locally on your Mac: detecting silence from the
          audio, transcribing filler words with an on-device speech model, and re-rendering the cut.
          Crisp only ever writes a new <code className={code}>…_cleaned</code> file and backs up your
          original first; it does not modify or delete your source. None of this involves the network.
        </p>
      ),
    },
    {
      heading: "3. When Crisp connects to the internet",
      body: (
        <>
          <p>For full transparency, these are the only times the app reaches the internet:</p>
          <ul className="mt-3 list-disc space-y-2 pl-5">
            <li>
              <Caps>First-run model download.</Caps> The first time you remove filler words, Crisp
              downloads a speech model (~148&nbsp;MB) once from{" "}
              <A href="https://huggingface.co/ggerganov/whisper.cpp">Hugging Face</A>. This is a plain
              file download; no personal data is sent. That request is subject to Hugging Face’s
              privacy policy.
            </li>
            <li>
              <Caps>Update checks.</Caps> Stable and Nightly builds query the{" "}
              <A href="https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement">
                GitHub
              </A>{" "}
              API to see whether a newer version exists, and download it only if you choose to update.
              GitHub may log standard request metadata (such as your IP address) under its own policy.
            </li>
            <li>
              <Caps>Installation via Homebrew.</Caps> If you install with Homebrew, the download comes
              from GitHub Releases and is handled by Homebrew and GitHub.
            </li>
          </ul>
          <p className="mt-3">
            That is the complete list. No analytics, telemetry, crash reporting, advertising, or
            third-party SDK is bundled with Crisp.
          </p>
        </>
      ),
    },
    {
      heading: "4. Information we collect",
      body: (
        <p>
          <Caps>None.</Caps> Because we run no servers that receive your data and have no account
          system, there is nothing for us to collect, profile, share, or sell. We have never sold or
          “shared” personal information and never will. For the purposes of data-protection laws, the
          data controller / business responsible for Crisp is {AUTHOR}, established in Pakistan; you can
          reach us using the contact details at the end of this policy.
        </p>
      ),
    },
    {
      heading: "5. Your privacy rights, worldwide",
      body: (
        <>
          <p>
            Crisp processes your recordings only on your device and we collect no personal data, so for
            most people there is simply nothing for us to hold, disclose, or delete. Even so, we honor
            the rights granted by privacy laws around the world. If you believe we hold any information
            about you (for example, an email you sent us), you may ask us to access, correct, delete,
            or port it, or to restrict or object to its processing — just contact us. We will not
            discriminate against you for exercising any right.
          </p>
          <ul className="mt-3 list-disc space-y-2 pl-5">
            <li>
              <Caps>European Economic Area &amp; Switzerland (GDPR).</Caps> Where we process any
              personal data, our legal basis is our legitimate interest in operating and improving
              Crisp, or your consent. You have the rights of access, rectification, erasure,
              restriction, portability, and objection, and the right to lodge a complaint with your
              local data-protection authority. We do not engage in automated decision-making or sell
              your data.
            </li>
            <li>
              <Caps>United Kingdom (UK GDPR &amp; Data Protection Act 2018).</Caps> You have the same
              rights as above and may complain to the UK Information Commissioner’s Office (ICO).
            </li>
            <li>
              <Caps>United States (CCPA/CPRA &amp; other state laws).</Caps> The categories of personal
              information we collect, sell, or share is: <Caps>none</Caps>. You have the rights to know,
              access, delete, correct, and opt out of sale/sharing — though there is nothing to opt out
              of, because we do neither.
            </li>
            <li>
              <Caps>China (PIPL).</Caps> Crisp runs locally on your device; we do not collect your
              personal information or transfer it outside of China (or anywhere). Any third-party
              downloads in Section 3 are made directly between your device and those providers.
            </li>
            <li>
              <Caps>Other regions (Canada PIPEDA, Australia, India, Japan, Korea, Brazil LGPD, and
              elsewhere in Asia and beyond).</Caps> The same applies: we collect nothing through the
              app, and we will honor any applicable right you assert under your local law. Contact us
              and we will respond as that law requires.
            </li>
          </ul>
        </>
      ),
    },
    {
      heading: "6. This website",
      body: (
        <p>
          This site is a static marketing page. It sets no cookies and runs no analytics or tracking
          scripts. Whoever hosts the site may keep standard server access logs (for example IP address
          and user agent) for security and operations under their own policy. Outbound links — to
          GitHub, Hugging Face, brew.sh, and {AUTHOR_URL.replace("https://", "")} — are governed by
          those sites’ own policies, which we do not control and are not responsible for.
        </p>
      ),
    },
    {
      heading: "7. Security",
      body: (
        <p>
          Because Crisp processes your recordings locally and transmits none of them, your content
          stays under your control on your own device. No method of storage or transmission is ever
          100% secure, and you are responsible for the security of your Mac and your files.
        </p>
      ),
    },
    {
      heading: "8. Children",
      body: (
        <p>
          Crisp is not directed to children under 13 (or the minimum age in your jurisdiction), and in
          any case the app knowingly collects no personal information from anyone, including children.
        </p>
      ),
    },
    {
      heading: "9. International users",
      body: (
        <p>
          Crisp runs on your device wherever you are; we do not transfer your personal data across
          borders because we do not collect it. The limited third-party requests described in Section
          3 are made directly between your device and those providers under their policies.
        </p>
      ),
    },
    {
      heading: "10. Changes to this policy",
      body: (
        <p>
          We may update this policy from time to time. Material changes will be reflected here with a
          new “last updated” date, and your continued use of Crisp or this site after that constitutes
          acceptance of the updated policy.
        </p>
      ),
    },
    {
      heading: "11. Open source & contact",
      body: (
        <p>
          Crisp is open source under the GPL-3.0; you can verify everything above in{" "}
          <A href={REPO}>the source code</A>. Questions, requests, or privacy concerns? {contactLine}.
        </p>
      ),
    },
  ],
};

export const termsDoc: LegalDoc = {
  title: "Terms of Use",
  updated: UPDATED,
  note: NOT_ADVICE,
  intro: (
    <>
      These Terms of Use (“Terms”) govern your use of the Crisp application and this website, both
      provided by {AUTHOR} (“we,” “us”). Crisp is free, open-source software; these plain-language
      Terms sit alongside the <A href={`${REPO}/blob/main/LICENSE`}>GNU General Public License v3.0</A>{" "}
      (“GPL-3.0”), which legally governs the source code. Please read them carefully.
    </>
  ),
  sections: [
    {
      heading: "1. Acceptance & eligibility",
      body: (
        <p>
          By downloading, installing, or using Crisp, or by using this website, you agree to these
          Terms. If you do not agree, do not use them. You must be the age of majority in your
          jurisdiction (or have your guardian’s consent), and if you use Crisp on behalf of an
          organization you represent that you have authority to bind it to these Terms.
        </p>
      ),
    },
    {
      heading: "2. Licence",
      body: (
        <p>
          Crisp is free and open-source software licensed under the GPL-3.0. You may use, study,
          modify, and redistribute it under the terms of that licence, which controls for anything
          concerning the source code. These Terms govern your use of the distributed app and this site.
        </p>
      ),
    },
    {
      heading: "3. No warranty",
      body: (
        <p>
          <Caps>
            CRISP AND THIS WEBSITE ARE PROVIDED “AS IS” AND “AS AVAILABLE,” WITHOUT WARRANTY OF ANY
            KIND, WHETHER EXPRESS, IMPLIED, OR STATUTORY.
          </Caps>{" "}
          To the fullest extent permitted by law, we disclaim all warranties, including merchantability,
          fitness for a particular purpose, title, non-infringement, accuracy, and any warranty that the
          software will be uninterrupted, timely, secure, error-free, or that it will detect every pause
          or filler, produce any particular result, or preserve any file. You use Crisp at your own risk.
        </p>
      ),
    },
    {
      heading: "4. Assumption of risk & your responsibilities",
      body: (
        <p>
          Software can fail. Although Crisp is designed never to modify or delete your originals and to
          back them up first, <Caps>you are responsible for keeping your own backups</Caps> of anything
          important and for reviewing Crisp’s output before relying on it. You accept the risk of any
          data loss, incorrect cuts, or unsatisfactory results, and you are solely responsible for the
          recordings you process and how you use the results.
        </p>
      ),
    },
    {
      heading: "5. Limitation of liability",
      body: (
        <p>
          <Caps>
            TO THE MAXIMUM EXTENT PERMITTED BY LAW, {AUTHOR.toUpperCase()} AND ITS CONTRIBUTORS SHALL NOT
            BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE
            DAMAGES, OR FOR ANY LOSS OF DATA, PROFITS, REVENUE, OR GOODWILL,
          </Caps>{" "}
          arising out of or relating to your use of (or inability to use) Crisp or this website, even if
          advised of the possibility of such damages. Our total aggregate liability for all claims shall
          not exceed the greater of the amount you paid us for Crisp (which is normally zero) or USD
          $50. Some jurisdictions do not allow certain exclusions or limitations, so parts of this
          section may not apply to you; in that case our liability is limited to the smallest extent
          permitted by law.
        </p>
      ),
    },
    {
      heading: "6. Indemnification",
      body: (
        <p>
          You agree to indemnify and hold harmless {AUTHOR} and its contributors from any claims,
          damages, liabilities, and expenses (including reasonable legal fees) arising out of your use
          of Crisp, the content you process with it, your violation of these Terms, or your violation of
          any law or the rights of a third party.
        </p>
      ),
    },
    {
      heading: "7. Third-party components & services",
      body: (
        <p>
          Crisp drives bundled open-source tools — including <A href="https://ffmpeg.org">FFmpeg</A>,{" "}
          <A href="https://github.com/ggerganov/whisper.cpp">whisper.cpp</A>, a Python runtime, and a
          speech model — and connects to third-party services (Hugging Face, GitHub, Homebrew), each
          under its own licence and terms. We do not control and are not responsible for those
          components or services, and your use of them is at your own risk and subject to their terms.
        </p>
      ),
    },
    {
      heading: "8. Pre-release builds",
      body: (
        <p>
          Nightly and Dev builds are experimental, may be unstable or change without notice, and are
          provided for testing only. They carry the same disclaimers as above, and you should not rely
          on them for important work.
        </p>
      ),
    },
    {
      heading: "9. Acceptable use",
      body: (
        <p>
          You may use Crisp only on recordings you own or have the right to edit, and only for lawful
          purposes. You must not use Crisp to create, process, or distribute content that is illegal or
          that infringes the rights of others, and you must comply with all applicable laws, including
          export-control and sanctions laws. You are solely responsible for your content and your use of
          the results.
        </p>
      ),
    },
    {
      heading: "10. Intellectual property & trademarks",
      body: (
        <p>
          The “Crisp” name, logo, icon, and the content of this website are © {AUTHOR} and protected by
          applicable law. The GPL-3.0 applies to the source code, not to the project’s name or branding;
          nothing here grants you a right to use our marks except as the GPL or applicable law allows.
        </p>
      ),
    },
    {
      heading: "11. Termination & survival",
      body: (
        <p>
          These Terms apply while you use Crisp or this site. Your rights under them end automatically if
          you breach them; you may stop using Crisp at any time. The disclaimers, limitation of
          liability, indemnification, and the “General” section survive any termination.
        </p>
      ),
    },
    {
      heading: "12. Changes; no obligation to support",
      body: (
        <p>
          We may modify, suspend, or discontinue Crisp, this website, or these Terms at any time, and we
          are under no obligation to provide support, updates, or maintenance. Material changes to these
          Terms will be reflected here with a new date; your continued use means you accept them.
        </p>
      ),
    },
    {
      heading: "13. Governing law & disputes",
      body: (
        <p>
          These Terms are governed by the laws of {JURISDICTION}, without regard to conflict-of-law
          rules, and the courts of Pakistan have non-exclusive jurisdiction over any dispute. You agree
          to first try to resolve any dispute informally by contacting us. To the extent permitted by
          law, any claim must be brought within one (1) year after it arises, or it is permanently
          barred. <Caps>However, if you use Crisp as a consumer, this section does not deprive you of
          the protection of the mandatory laws of your country of residence</Caps> (for example, in the
          EEA, the UK, or other regions), and you may also be able to bring proceedings in your local
          courts; nothing in these Terms waives consumer rights that cannot be waived under your local
          law.
        </p>
      ),
    },
    {
      heading: "14. General",
      body: (
        <p>
          If any provision of these Terms is held unenforceable, the rest remain in effect and the
          unenforceable part is limited to the minimum extent necessary. These Terms, together with the
          GPL-3.0 and our <A href="/privacy">Privacy Policy</A>, are the entire agreement between us
          regarding their subject matter. Our failure to enforce a provision is not a waiver. You may
          not assign these Terms; we may. We are not liable for events beyond our reasonable control.
          Section headings are for convenience only.
        </p>
      ),
    },
    {
      heading: "15. Contact",
      body: <p>Questions about these Terms? {contactLine}.</p>,
    },
  ],
};
