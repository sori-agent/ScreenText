"""Sign the local build with a stable development identity when one is available."""

import os
import re
import subprocess
import sys
from pathlib import Path


def signing_identity() -> str:
    """Use an explicit identity or this Mac's sole Apple Development certificate."""
    if identity := os.environ.get("SCREENTEXT_SIGNING_IDENTITY"):
        return identity
    result = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                            check=True, capture_output=True, text=True)
    identities = re.findall(r'\d+\)\s+([A-F0-9]{40}) "Apple Development: [^"]+"', result.stdout)
    return identities[0] if len(identities) == 1 else "-"


def sign_app(app: Path, identity: str) -> None:
    """Repair the vendor framework layout in the build copy, then verify its signature."""
    for name in ("Leptonica", "TesseractCore"):
        framework = app / "Contents/Frameworks" / f"{name}.framework"
        extra = framework / "Info.plist"
        # These vendor links duplicate the plist in Resources and invalidate framework sealing.
        if extra.is_symlink() and extra.readlink() == Path("Versions/Current/Resources/Info.plist"):
            extra.unlink()
        subprocess.run(["codesign", "--force", "--sign", identity,
                        "--preserve-metadata=identifier,entitlements,flags", str(framework)], check=True)
    subprocess.run(["codesign", "--force", "--sign", identity,
                    "--preserve-metadata=identifier,entitlements,flags", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    app = Path(sys.argv[1]) if len(sys.argv) > 1 else root / ".local/DerivedData/Build/Products/Debug/ScreenText.app"
    identity = signing_identity()
    sign_app(app, identity)
    if identity == "-":
        print("Ad-hoc signing: rebuilding can require a fresh Screen Recording grant.")
    else:
        print("Signed with a stable Apple Development identity.")
