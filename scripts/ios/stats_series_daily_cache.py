#!/usr/bin/env python3
"""Selected-date body fat must come from the daily chart, not a later or trend sample.

Launch Quality run 44689925709 failed
MetricStatsSeriesStoreTests.testSummariesBuildOnceForTheSameFingerprintAndSkipASelectedDateChange
because the only daily body-fat point was after the selected date. The summary
correctly returned nil. This check fails before that native suite runs.
"""

from pathlib import Path
import re
import sys

DAILY_MISS = 'daily body-fat fixture has no sample on or before the selected date'
TREND_MISS = 'trend body-fat fixture has no sample on the selected date'
SAME_VALUE = 'daily and trend body-fat values must differ at the selected date'
WRONG_EXPECTATION = 'selected-date body-fat assertion does not expect the daily cache value'
LOST_DAILY = 'body-fat summary lost the daily chart'
LOST_DATE = 'body-fat summary lost the selected date'
READS_TREND = 'body-fat summary reads the trend cache'
LOST_WEIGHT = 'weight summary lost the trend series'
LOST_WEIGHT_DATE = 'weight summary lost the selected date'

STORE = Path('apps/ios/LogYourBody/Helpers/MetricStatsSeriesStore.swift')
TESTS = Path('apps/ios/LogYourBodyTests/MetricStatsSeriesStoreTests.swift')
DAILY_SERIES = '.bodyFat: [point(earlier, bodyFat), point(now, bodyFat)]'
FUTURE_SERIES = '.bodyFat: [point(now, bodyFat)]'


def _swift_body(source, name):
    match = re.search(rf'\bfunc {re.escape(name)}\b', source)
    if not match:
        return ''
    rest = source[match.end():]
    nxt = re.search(r'\n    (?:private )?func ', rest)
    return rest[:nxt.start()] if nxt else rest


def _between(text, start, end):
    if start not in text:
        return ''
    chunk = text.split(start, 1)[1]
    return chunk.split(end, 1)[0] if end in chunk else chunk


def _series(body, label):
    match = re.search(rf'\.{label}:\s*\[(.*?)\]', body, re.S)
    return match.group(1) if match else ''


def _body_fat_literal(method, function):
    match = re.search(
        rf'\b{function}\(\s*weight:\s*\([^)]*\),\s*bodyFat:\s*([0-9][0-9_]*)', method)
    return match.group(1).replace('_', '') if match else ''


def findings(store, tests):
    """Return contract misses. An empty list is the only passing result."""
    found = []
    match = re.search(r'func summaries\(_ input: Input\)[\s\S]*?\n    \}', store)
    summaries = match.group(0) if match else ''
    weight = _between(summaries, '.weight:', '.bodyFat:')
    fat = _between(summaries, '.bodyFat:', '.ffmi:')
    if 'weightSeries(usesTrend:' not in summaries:
        found.append(LOST_WEIGHT)
    if 'selectedDate: input.selectedDate' not in weight:
        found.append(LOST_WEIGHT_DATE)
    if 'points: chart[.bodyFat]' not in fat:
        found.append(LOST_DAILY)
    if 'selectedDate: input.selectedDate' not in fat:
        found.append(LOST_DATE)
    if 'trend[.bodyFat]' in fat:
        found.append(READS_TREND)
    method = _swift_body(tests, 'testSummariesBuildOnceForTheSameFingerprintAndSkipASelectedDateChange')
    if 'point(earlier, bodyFat)' not in _series(_swift_body(tests, 'chart'), 'bodyFat'):
        found.append(DAILY_MISS)
    if 'point(earlier, bodyFat)' not in _series(_swift_body(tests, 'trend'), 'bodyFat'):
        found.append(TREND_MISS)
    daily = _body_fat_literal(method, 'chart')
    smoothed = _body_fat_literal(method, 'trend')
    if not daily or daily == smoothed:
        found.append(SAME_VALUE)
    expected = re.search(r'first\[\.bodyFat\]\?\.point\?\.value,\s*([0-9_]+)', method)
    if not expected or expected.group(1).replace('_', '') != daily:
        found.append(WRONG_EXPECTATION)
    return found


def _require(actual, message):
    if message not in actual:
        raise AssertionError(f'{message} not reported; got {actual}')


def check_repository(root):
    root = Path(root)
    store = (root / STORE).read_text()
    tests = (root / TESTS).read_text()
    actual = findings(store, tests)
    if actual:
        raise AssertionError('stats series daily cache contract failed:\n' + '\n'.join(actual))
    _require(findings(store, tests.replace(DAILY_SERIES, FUTURE_SERIES, 1)), DAILY_MISS)
    _require(findings(store.replace('points: chart[.bodyFat]', 'points: trend[.bodyFat]', 1), tests), LOST_DAILY)
    _require(findings(store, tests.replace('bodyFat: 99', 'bodyFat: 20', 1)), SAME_VALUE)
    _require(
        findings(store, tests.replace(
            'first[.bodyFat]?.point?.value, 20', 'first[.bodyFat]?.point?.value, 99', 1)),
        WRONG_EXPECTATION)
    dropped_date = store.replace(
        'points: chart[.bodyFat] ?? [], range: input.range, selectedDate: input.selectedDate,',
        'points: chart[.bodyFat] ?? [], range: input.range,',
        1)
    _require(findings(dropped_date, tests), LOST_DATE)


def main():
    check_repository(Path(__file__).resolve().parents[2])
    print('stats series daily cache checks passed')


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
