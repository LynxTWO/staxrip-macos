#!/usr/bin/env python3
"""Inspect a local planner snapshot. Predictions cannot authorize publication.

Usage: python3 scripts/diagnose-gain-planner.py SNAPSHOT.json
Shift probes retain only the gain bounds; they intentionally do not enforce
Night excursion ceilings, smoothing or peak control. They are not candidates.
"""
import json
import math
import sys


def loudness(energy):
    return -0.691 + 10 * math.log10(energy) if energy > 0 else -math.inf


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[int((len(ordered) - 1) * fraction + 0.5)]


def measure(energies, envelope):
    prefix = [0.0]
    for index, energy in enumerate(energies):
        gain = (envelope[min(index, len(envelope)-1)] +
                envelope[min(index+1, len(envelope)-1)]) / 2
        prefix.append(prefix[-1] + energy * 10 ** (gain / 10))
    blocks = [max(0, (prefix[end] - prefix[end-20]) / 20)
              for end in range(20, len(energies)+1, 5)]
    absolute = [value for value in blocks if loudness(value) > -70]
    if not absolute:
        raise ValueError('Unmeasurable integrated loudness')
    gate = max(-70, loudness(sum(absolute)/len(absolute))-10)
    selected = [value for value in absolute if loudness(value) > gate]
    integrated = loudness(sum(selected)/len(selected))
    prefix.extend([prefix[-1]] * 75)
    windows = [max(0, (prefix[end] - prefix[end-150]) / 150)
               for end in range(150, len(energies)+76, 5)]
    absolute = [value for value in windows if loudness(value) > -70]
    if not absolute:
        raise ValueError('Unmeasurable loudness range')
    gate = max(-70, loudness(sum(absolute)/len(absolute))-20)
    levels = [loudness(value) for value in windows]
    membership = {index for index, value in enumerate(levels) if value > gate}
    selected = [levels[index] for index in membership]
    return dict(integrated=integrated, gate=gate, low=percentile(selected, .10),
                high=percentile(selected, .95)), levels, membership


def diagnose(snapshot):
    energies = snapshot['energies']
    source, _, source_membership = measure(energies, [0.0])
    result = {'source': source, 'probes': []}
    for mode in ('smart', 'night'):
        original = snapshot[mode]
        for shift in (0, 1, 3, 6, 9):
            envelope = [max(-36, min(12, value+shift)) for value in original]
            metrics, levels, membership = measure(energies, envelope)
            if shift == 0:
                swift = snapshot[mode+'Prediction']
                calculated = [metrics[key] for key in ('integrated', 'low', 'high')]
                if max(abs(a-b) for a, b in zip(swift, calculated)) > 1e-6:
                    raise ValueError('Diagnostic calculation disagrees with Swift prediction')
            fixed = [levels[index] for index in source_membership]
            result['probes'].append(dict(mode=mode, shiftDB=shift, **metrics,
                lra=metrics['high']-metrics['low'],
                sourceGateMembershipLRA=percentile(fixed, .95)-percentile(fixed, .10),
                newlyIncludedWindows=len(membership-source_membership),
                excludedSourceWindows=len(source_membership-membership),
                includedWindows=len(membership),
                binsAtBoostLimit=sum(value >= 12-1e-9 for value in envelope),
                binsWithinPointOneOfBoostLimit=sum(value >= 11.9 for value in envelope),
                totalBins=len(envelope)))
    return result


if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']:
        energy = 10 ** ((-23 + .691) / 10)
        for gain in (-12, 0, 6):
            measured, _, _ = measure([energy]*4000, [gain])
            assert abs(measured['integrated']-(-23+gain)) < 1e-8
            assert abs(measured['high']-measured['low']) < 1e-8
        try:
            measure([0.0]*4000, [0.0])
        except ValueError:
            pass
        else:
            raise AssertionError('Silence must be unmeasurable')
        print('Known-energy gain and silence checks passed')
    else:
        with open(sys.argv[1], encoding='utf-8') as stream:
            snapshot = json.load(stream)
        print(json.dumps(diagnose(snapshot), indent=2, allow_nan=False))
