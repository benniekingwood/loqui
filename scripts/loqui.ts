import { access, mkdtemp, mkdir, rename, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import {
  launchMacApplication,
  stopMacApplication,
} from "./macos-app-lifecycle";

const repositoryRoot = resolve(import.meta.dir, "..");
const sourceAppPath = join(repositoryRoot, "Loqui.app");
const applicationsPath = "/Applications";
const installedAppPath = join(applicationsPath, "Loqui.app");
const installedExecutablePath = join(
  installedAppPath,
  "Contents",
  "MacOS",
  "Loqui",
);

type SigningConfiguration = {
  mode: "adhoc" | "apple-development";
  environment: Record<string, string>;
  summary: string;
};

async function run(
  command: string[],
  environment: Record<string, string> = {},
) {
  const child = Bun.spawn(command, {
    cwd: repositoryRoot,
    env: { ...process.env, ...environment },
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  const exitCode = await child.exited;
  if (exitCode !== 0) {
    throw new Error(`Command failed (${exitCode}): ${command.join(" ")}`);
  }
}

async function capture(command: string[], input?: Blob) {
  const child = Bun.spawn(command, {
    cwd: repositoryRoot,
    stdin: input ?? "ignore",
    stdout: "pipe",
    stderr: "ignore",
  });
  const output = await new Response(child.stdout).text();
  return { exitCode: await child.exited, output };
}

async function localSigningConfiguration(): Promise<SigningConfiguration> {
  const identities = await capture([
    "/usr/bin/security",
    "find-identity",
    "-v",
    "-p",
    "codesigning",
  ]);
  const candidates =
    identities.exitCode === 0
      ? [...identities.output.matchAll(/"(Apple Development: [^"]+)"/g)].map(
          (match) => match[1],
        )
      : [];

  // A keychain can hold Apple Development identities for several teams, so
  // prefer the project's team and fall back to the first one for other
  // checkouts.
  const preferredTeamID =
    process.env.LOQUI_DEVELOPMENT_TEAM || "K78G42H4U2";
  let selected: { identity: string; teamID: string } | undefined;

  for (const identity of candidates) {
    const certificate = await capture([
      "/usr/bin/security",
      "find-certificate",
      "-c",
      identity,
      "-p",
    ]);
    const subject = await capture(
      ["/usr/bin/openssl", "x509", "-noout", "-subject"],
      new Blob([certificate.output]),
    );
    const teamID = subject.output.match(
      /(?:^|[,/])\s*OU\s*=\s*([A-Z0-9]+)/,
    )?.[1];

    if (certificate.exitCode !== 0 || subject.exitCode !== 0 || !teamID) {
      continue;
    }
    if (!selected || teamID === preferredTeamID) {
      selected = { identity, teamID };
    }
    if (teamID === preferredTeamID) {
      break;
    }
  }

  if (selected) {
    const { identity, teamID } = selected;
    return {
      mode: "apple-development",
      environment: {
        LOQUI_SIGNING_MODE: "apple-development",
        LOQUI_SIGNING_IDENTITY: identity,
        LOQUI_EXPECTED_TEAM_ID: teamID,
      },
      summary: `${identity} (team ${teamID})`,
    };
  }

  console.warn(
    "warning: no Apple Development identity found; falling back to ad-hoc signing.\n" +
      "         macOS permission grants may need to be renewed after each deployment.",
  );
  return {
    mode: "adhoc",
    environment: { LOQUI_SIGNING_MODE: "adhoc" },
    summary: "ad-hoc",
  };
}

async function pathExists(path: string) {
  try {
    await access(path);
    return true;
  } catch (error) {
    if ((error as { code?: string }).code === "ENOENT") {
      return false;
    }
    throw error;
  }
}

async function deploy(signing: SigningConfiguration) {
  await mkdir(applicationsPath, { recursive: true });

  // /Applications is group-writable by admin. A standard account cannot stage
  // there, and the failure is worth naming rather than surfacing as EACCES.
  let transactionPath: string;
  try {
    transactionPath = await mkdtemp(join(applicationsPath, ".loqui-install-"));
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "EACCES" || code === "EPERM") {
      throw new Error(
        `${applicationsPath} is not writable by this account. ` +
          "Deploy from an administrator account, or install Loqui.app there by hand.",
      );
    }
    throw error;
  }
  const stagedAppPath = join(transactionPath, "Loqui.app");
  const previousAppPath = join(transactionPath, "previous-Loqui.app");
  let previousAppWasMoved = false;

  try {
    console.log(`==> Staging ${installedAppPath}...`);
    await run(["/usr/bin/ditto", sourceAppPath, stagedAppPath]);
    await run(
      [join(repositoryRoot, "scripts", "verify-bundle.sh"), stagedAppPath],
      {
        ...signing.environment,
        LOQUI_EXPECTED_SIGNATURE: signing.mode,
      },
    );

    if (await pathExists(installedAppPath)) {
      await rename(installedAppPath, previousAppPath);
      previousAppWasMoved = true;
    }

    try {
      await rename(stagedAppPath, installedAppPath);
    } catch (error) {
      if (previousAppWasMoved) {
        await rename(previousAppPath, installedAppPath);
        previousAppWasMoved = false;
      }
      throw error;
    }

    if (previousAppWasMoved) {
      await rm(previousAppPath, { recursive: true, force: true });
      previousAppWasMoved = false;
    }
  } finally {
    if (previousAppWasMoved && !(await pathExists(installedAppPath))) {
      await rename(previousAppPath, installedAppPath);
      previousAppWasMoved = false;
    }
    await rm(transactionPath, { recursive: true, force: true });
  }
}

if (process.platform !== "darwin") {
  throw new Error("`bun loqui` can only build and deploy Loqui on macOS.");
}

const signing = await localSigningConfiguration();
console.log("==> Building the self-contained Universal 2 Loqui app...");
console.log(`    Signing: ${signing.summary}`);
await run([join(repositoryRoot, "bundle.sh")], signing.environment);

const wasRunning = await stopMacApplication({
  bundleIdentifier: "com.benniekingwood.loqui",
  displayName: "Loqui",
});
await deploy(signing);

if (!(await Bun.file(installedExecutablePath).exists())) {
  throw new Error(
    `Deployment completed but the Loqui executable is missing at ${installedExecutablePath}.`,
  );
}

if (wasRunning) {
  console.log("==> Restarting the installed Loqui app...");
  await launchMacApplication({
    appPath: installedAppPath,
    executablePath: installedExecutablePath,
    executableName: "Loqui",
    displayName: "Loqui",
  });
}

console.log(`==> Loqui deployed: ${installedAppPath}`);
