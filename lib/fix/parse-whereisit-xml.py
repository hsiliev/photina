#!/usr/bin/env python3
"""Emit target-file metadata from a WhereIsIt XML report as TSV.

The output columns match the find(1) metadata consumed by fix-flickr-names.sh:
name, size, mtime epoch, birth epoch, mtime date, birth date, and path.
Only the XML report is read; no media file is opened.
"""

import re
import sys
import time
import xml.etree.ElementTree as ET


DATE_TIME_RE = re.compile(
    r"(?:Camera|Digitized) Date and Time:\s*"
    r"(?:(?P<day>\d{1,2})\.(?P<month>\d{1,2})\.(?P<year>\d{4})\s+г\.,\s*"
    r"(?P<local_time>\d{2}:\d{2}:\d{2})|"
    r"(?P<iso_year>\d{4}):(?P<iso_month>\d{2}):(?P<iso_day>\d{2})\s+"
    r"(?P<iso_time>\d{2}:\d{2}:\d{2}))"
)


def epoch(value):
    if not value:
        return ""
    try:
        parts = time.strptime(value, "%Y:%m:%d %H:%M:%S")
        return str(int(time.mktime(parts)))
    except ValueError:
        return ""


def text(item, tag):
    value = item.findtext(tag)
    return value.strip() if value else ""


def main(path):
    for item in ET.parse(path).getroot().iter("ITEM"):
        if item.get("ItemType") != "File":
            continue

        name = text(item, "NAME")
        extension = text(item, "EXT")
        if not name:
            continue
        if extension and not name.lower().endswith("." + extension.lower()):
            name += "." + extension

        description = text(item, "DESCRIPTION")
        dates = []
        for match in DATE_TIME_RE.finditer(description):
            if match.group("day"):
                dates.append(
                    f"{match.group('year')}:{int(match.group('month')):02d}:"
                    f"{int(match.group('day')):02d} {match.group('local_time')}"
                )
            else:
                dates.append(
                    f"{match.group('iso_year')}:{match.group('iso_month')}:"
                    f"{match.group('iso_day')} {match.group('iso_time')}"
                )
        camera_date = dates[0] if dates else ""
        digitized_date = dates[1] if len(dates) > 1 else ""
        disk_date = text(item, "DATE")

        # Keep the two extracted timestamps in the same fields used by the
        # directory mode. Filename-date matching remains available as well.
        mtime = epoch(camera_date)
        birthtime = epoch(digitized_date)
        mtime_date = camera_date[:10] if camera_date else disk_date.replace("-", ":")
        birth_date = digitized_date[:10] if digitized_date else ""

        fields = [
            name,
            text(item, "SIZE"),
            mtime,
            birthtime,
            mtime_date,
            birth_date,
            text(item, "PATH"),
        ]
        print("\t".join(fields))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: parse-whereisit-xml.py XML_FILE")
    main(sys.argv[1])
