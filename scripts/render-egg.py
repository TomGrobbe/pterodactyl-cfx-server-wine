#!/usr/bin/env python3
import argparse
import datetime
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "egg-cfx-server-wine.template.json"
INSTALL = ROOT / "scripts" / "install.sh"
OUTPUT = ROOT / "egg-cfx-server-wine.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--owner", required=True, help="GitHub user or org that owns the image")
    parser.add_argument("--image", default="cfx-server-wine", help="image name inside the registry")
    parser.add_argument("--tag", default="latest", help="image tag the egg should use")
    parser.add_argument("--output", default=str(OUTPUT))
    args = parser.parse_args()

    owner = args.owner.lower()
    reference = f"ghcr.io/{owner}/{args.image}:{args.tag}"

    egg = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    egg["exported_at"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    egg["scripts"]["installation"]["script"] = INSTALL.read_text(encoding="utf-8")
    egg["docker_images"] = {
        name: image.replace("ghcr.io/OWNER/cfx-server-wine:latest", reference)
        for name, image in egg["docker_images"].items()
    }

    if any("OWNER" in image for image in egg["docker_images"].values()):
        print("placeholder owner survived rendering", file=sys.stderr)
        return 1

    out = pathlib.Path(args.output)

    if out.exists():
        try:
            previous = json.loads(out.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            previous = None
        if previous is not None:
            stamp = previous.get("exported_at")
            if dict(egg, exported_at=stamp) == previous:
                egg["exported_at"] = stamp

    out.write_text(json.dumps(egg, indent=4) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {out} -> {reference}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
