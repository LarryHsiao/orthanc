#!/usr/bin/env python3
"""Add or replace one platform's <item> in appcast.xml.

Called by publish_macos.sh (macOS, --ed-signature) and release_github.ps1
(Windows, --dsa-signature) after a release is signed and uploaded. Removes
any existing <item> for the same sparkle:os first, so re-running a publish
for a platform replaces that platform's entry rather than duplicating it —
the other platform's item, if present, is left untouched.

Usage (macOS):
  update_appcast.py --appcast appcast.xml --os macos --version 1.1.4 \
    --build 8 --pub-date "Tue, 28 Jul 2026 12:00:00 +0000" \
    --url https://github.com/.../orthanc.dmg --length 21275410 \
    --ed-signature "..."

Usage (Windows):
  update_appcast.py --appcast appcast.xml --os windows --version 1.1.4 \
    --full-version 1.1.4+7 \
    --pub-date "Tue, 28 Jul 2026 12:00:00 +0000" \
    --url https://github.com/.../orthanc-setup-1.1.4.exe --length 12345678 \
    --dsa-signature "..."

--full-version must match the built exe's ProductVersion string exactly
(pubspec.yaml's version field, e.g. "1.1.4+7") — WinSparkle compares
sparkle:version against that resource value, not against --version.
"""

import argparse
import sys
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)


def sparkle_tag(name: str) -> str:
    return f"{{{SPARKLE_NS}}}{name}"


def build_item(args: argparse.Namespace) -> ET.Element:
    item = ET.Element("item")

    title = ET.SubElement(item, "title")
    title.text = f"Version {args.version}"

    if args.os == "macos":
        version_el = ET.SubElement(item, sparkle_tag("version"))
        version_el.text = args.build
        short_version_el = ET.SubElement(item, sparkle_tag("shortVersionString"))
        short_version_el.text = args.version

    pub_date = ET.SubElement(item, "pubDate")
    pub_date.text = args.pub_date

    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", args.url)
    if args.os == "macos":
        enclosure.set(sparkle_tag("edSignature"), args.ed_signature)
    else:
        enclosure.set(sparkle_tag("dsaSignature"), args.dsa_signature)
        enclosure.set(sparkle_tag("version"), args.full_version)
    enclosure.set(sparkle_tag("os"), args.os)
    enclosure.set("length", args.length)
    enclosure.set("type", "application/octet-stream")

    return item


def item_os(item: ET.Element) -> str | None:
    enclosure = item.find("enclosure")
    if enclosure is None:
        return None
    return enclosure.get(sparkle_tag("os"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--os", required=True, choices=["macos", "windows"])
    parser.add_argument("--version", required=True, help="e.g. 1.1.4")
    parser.add_argument("--build", help="macOS only: the +N build number")
    parser.add_argument(
        "--full-version",
        help="Windows only: full pubspec version incl. build suffix "
        "(e.g. 1.1.4+7), must match the exe's ProductVersion exactly",
    )
    parser.add_argument("--pub-date", required=True, help="RFC 2822, e.g. 'Tue, 28 Jul 2026 12:00:00 +0000'")
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", required=True)
    parser.add_argument("--ed-signature", help="macOS only")
    parser.add_argument("--dsa-signature", help="Windows only")
    args = parser.parse_args()

    if args.os == "macos" and not (args.build and args.ed_signature):
        parser.error("--os macos requires --build and --ed-signature")
    if args.os == "windows" and not (args.dsa_signature and args.full_version):
        parser.error("--os windows requires --dsa-signature and --full-version")

    tree = ET.parse(args.appcast)
    channel = tree.getroot().find("channel")
    if channel is None:
        print(f"error: no <channel> found in {args.appcast}", file=sys.stderr)
        return 1

    for existing in list(channel.findall("item")):
        if item_os(existing) == args.os:
            channel.remove(existing)

    channel.append(build_item(args))

    ET.indent(tree, space="    ")
    tree.write(args.appcast, encoding="UTF-8", xml_declaration=True)
    with open(args.appcast, "a") as f:
        f.write("\n")

    print(f"==> appcast.xml updated: {args.os} v{args.version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
