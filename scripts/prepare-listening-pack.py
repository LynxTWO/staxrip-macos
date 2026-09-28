#!/usr/bin/env python3
"""Local S2-008 listening preparation. Never uploads media or changes app defaults."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import random
import re
import shutil
import subprocess


def run(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True)


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            result.update(block)
    return result.hexdigest()


def measure(ffmpeg, path):
    result = run([ffmpeg, '-hide_banner', '-nostdin', '-i', str(path), '-af',
                  'ebur128=metadata=1:peak=true,ametadata=print', '-f', 'null', '-'])
    def last(pattern):
        matches = re.findall(pattern, result.stderr)
        if not matches:
            raise ValueError('Missing loudness measurement')
        return float(matches[-1])
    # Metadata retains milliloudness precision; the peak summary is in dB.
    # Use the app's unpadded ebur128 measurement path, not loudnorm's analysis.
    values = dict(input_i=last(r'lavfi\.r128\.I=(-?[0-9.]+)'),
                  input_lra=last(r'lavfi\.r128\.LRA=(-?[0-9.]+)'),
                  input_tp=last(r'Peak:\s+(-?[0-9.]+)'))
    if not all(math.isfinite(value) for value in values.values()):
        raise ValueError('Excerpt measurement is unavailable')
    return values


def encode(ffmpeg, source, output, filters):
    run([ffmpeg, '-hide_banner', '-nostdin', '-v', 'error', '-xerror', '-n',
         '-i', str(source), '-map', '0:a:0', '-af', filters, '-map_metadata', '-1',
         '-map_chapters', '-1', '-c:a', 'flac', '-sample_fmt', 's32',
         '-bits_per_raw_sample', '24', str(output)])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('source', 'smart', 'night', 'legacy', 'output'):
        parser.add_argument('--'+key, type=Path, required=True)
    args = parser.parse_args()
    ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    if not ffmpeg or not ffprobe:
        raise RuntimeError('Install FFmpeg before preparing local media')
    expected = '7512d492a4d479a6c5ffe5429dce35077aab653bfdc8362a2529a6a4ce323306'
    if digest(args.source) != expected:
        raise ValueError('Source differs from the rights manifest')
    receipts = {}
    for name in ('smart', 'night'):
        audio = getattr(args, name)
        receipt = json.loads(audio.with_suffix('.json').read_text())
        if receipt['source']['sha256'] != expected or receipt['output']['sha256'] != digest(audio):
            raise ValueError('Master differs from its verified receipt')
        receipts[name] = receipt
    legacy_report = json.loads(args.legacy.with_name('LegacyNight-analysis.json').read_text())
    if legacy_report['source']['sha256'] != digest(args.legacy):
        raise ValueError('Legacy baseline differs from its fresh analysis')
    # Exclusive owned directory. A partial run remains visibly incomplete.
    args.output.mkdir(mode=0o700)
    (args.output/'INCOMPLETE.txt').write_text('Preparation has not finished. Do not rate these files yet.\n')
    staging = args.output/'.staging'; staging.mkdir()
    audit = args.output/'review-key'; audit.mkdir()
    before = receipts['smart']['before']
    constant_gain = min(-23-before['integrated']['value'], -1.5-before['truePeak']['value'])
    constant = staging/'constant-full.flac'
    encode(ffmpeg, args.source, constant, f'volume={constant_gain:.12f}dB')
    constant_measurement = measure(ffmpeg, constant)
    if constant_measurement['input_tp'] > -1:
        raise ValueError('Constant control failed peak verification')
    variants = dict(original=args.source, constant=constant, legacy=args.legacy,
                    smart=args.smart, night=args.night)
    manifest = dict(schemaVersion=1, purpose='Local owner listening screen, not production acceptance',
                    sourceSHA256=expected, ffmpeg=run([ffmpeg, '-version']).stdout.splitlines()[0],
                    matchingMeter='FFmpeg ebur128 unpadded integrated metadata; separate Swift check required',
                    attribution='Sintel (2010), © Blender Foundation, sintel.org. Modified stereo audio. CC BY 3.0.',
                    license='https://creativecommons.org/licenses/by/3.0/',
                    settings=dict(smart=receipts['smart']['settings'], night=receipts['night']['settings'],
                                  legacy=dict(mode='Existing FFmpeg Night / Venue', targetLUFS=-30, maximumLRA=20),
                                  constantGainDB=constant_gain), excerpts=[])
    rng = random.Random(9282026)
    for number, start in enumerate((100, 200, 245, 320, 440, 585), 1):
        group = args.output/f'{number:02}'; group.mkdir()
        cuts, readings = {}, {}
        for name, source in variants.items():
            cut = staging/f'{number:02}-{name}.flac'
            encode(ffmpeg, source, cut, f'atrim=start_sample={start*48000}:end_sample={(start+45)*48000},asetpts=PTS-STARTPTS')
            cuts[name] = cut; readings[name] = measure(ffmpeg, cut)
        # Attenuation only, with at least 3 dB measured true-peak headroom.
        target = min(min(value['input_i'] for value in readings.values()),
                     min(value['input_i']-3-value['input_tp'] for value in readings.values()))
        names = list(variants); rng.shuffle(names)
        entry = dict(number=number, startFrame=start*48000, frames=45*48000,
                     sampleRate=48000, matchedTargetLUFS=target, options=[])
        for label, name in zip('ABCDE', names):
            attenuation = target-readings[name]['input_i']
            if attenuation > 1e-9:
                raise ValueError('Matching unexpectedly requires amplification')
            destination = group/f'{label}.flac'
            encode(ffmpeg, cuts[name], destination, f'volume={attenuation:.12f}dB')
            result = measure(ffmpeg, destination)
            if abs(result['input_i']-target) > .1 or result['input_tp'] > -2.9:
                raise ValueError('Matched file missed level or peak check')
            probe = json.loads(run([ffprobe, '-v', 'error', '-show_streams', '-of', 'json', str(destination)]).stdout)['streams'][0]
            if (probe['codec_name'], probe['sample_rate'], probe['channels'], probe['duration_ts'], probe['time_base'], probe['bits_per_raw_sample']) != ('flac', '48000', 2, 45*48000, '1/48000', '24'):
                raise ValueError('Excerpt frame/format contract failed')
            entry['options'].append(dict(label=label, variant=name, attenuationDB=attenuation,
                                         sha256=digest(destination), measured=result))
        levels = [item['measured']['input_i'] for item in entry['options']]
        entry['maximumLevelDifferenceLU'] = max(levels)-min(levels)
        if entry['maximumLevelDifferenceLU'] > .2:
            raise ValueError('Excerpt comparison is not level matched')
        manifest['excerpts'].append(entry)
        print(f'Excerpt {number}: five aligned files, level spread {max(levels)-min(levels):.2f} LU', flush=True)
    (audit/'manifest.json').write_text(json.dumps(manifest, indent=2, allow_nan=False)+'\n')
    for name, receipt in receipts.items():
        (audit/(name+'-full-master.json')).write_text(json.dumps(receipt, indent=2)+'\n')
    with (args.output/'ratings.csv').open('x', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['Excerpt', 'Option', 'Intelligibility 1-5', 'Pumping 0-5', 'Transient damage 0-5',
                         'Stereo image damage 0-5', 'Fatigue 0-5', 'Prefer or tie', 'Coverage and notes'])
        for number in range(1, 7):
            for label in 'ABCDE':
                writer.writerow([number, label]+['']*7)
    instructions = '''# Local listening walkthrough

Open index.html in Safari, or use the project's scripts/serve-listening-pack.py with this folder to serve the page on localhost with audio seeking. Pick an excerpt, then compare A through E at the same playback position. Switching pauses playback. Set a comfortable volume for each excerpt, then keep it fixed while comparing its five options. Replay useful sections; take breaks as needed.

Fill ratings.csv before opening review-key/manifest.json. Score intelligibility from 1 (hard to follow) to 5 (clear). For pumping, transient damage, stereo damage and fatigue, 0 means none and 5 means severe. Ties are valid. Note timestamps, missing coverage, audible artifacts and anything you would change. Confirm whether these passages cover quiet speech, dialogue/action transitions, music under speech, transients, ambience and different speaker levels. Coverage is provisional until you listen.

All options are 45-second stereo excerpts from full-film processing, matched by attenuation only and freshly measured. Original and constant-gain versions should be nearly identical after matching; this is a control. Keep the comparison key closed until rating. The key discloses every setting, measurement and file hash.

These are wider-range research candidates, not a successful 3 LU Midnight master. Processing settings differ, so preferences do not establish algorithm superiority. This English-only, modified stereo mix cannot validate multilingual or surround processing. No listening-quality result has been supplied by the owner yet.

Sintel (2010), © Blender Foundation, https://www.sintel.org/ . Modified stereo audio, licensed under Creative Commons Attribution 3.0: https://creativecommons.org/licenses/by/3.0/ . No endorsement is implied. Media stays local and is excluded from Git.
'''
    (args.output/'README.md').write_text(instructions)
    (args.output/'index.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>StaxRip listening review</title>
<style>body{font:18px system-ui;max-width:780px;margin:48px auto;padding:0 24px;background:#111820;color:#edf3f8;line-height:1.6}select,button,audio{font:inherit;margin:8px 6px 8px 0}button,select{padding:10px 16px;border:1px solid #71869b;border-radius:8px;background:#253445;color:white}button[aria-pressed=true]{background:#205c79;border-color:#80dfff}a{color:#8de1ff}audio{width:100%}:focus-visible{outline:3px solid #ffdc86;outline-offset:3px}.note{color:#becbd6}</style>
<h1>Listen before choosing</h1><p>Six excerpts. Five concealed options in each. Choose a comfortable volume, then keep it fixed while comparing options.</p>
<label for="excerpt">Excerpt</label><select id="excerpt">'''+''.join(f'<option value="{i:02}">{i} of 6 · 45 seconds</option>' for i in range(1,7))+'''</select>
<div role="group" aria-label="Concealed audio options">'''+''.join(f'<button type="button" data-label="{label}" aria-pressed="false">Option {label}</button>' for label in 'ABCDE')+'''</div>
<p id="status" role="status">Excerpt 1, option A. Paused.</p><audio id="player" controls preload="metadata" aria-label="Level-matched listening excerpt"></audio>
<p class="note">Switching options pauses playback and preserves position. A new excerpt starts at zero. Press Play when ready.</p>
<p><a href="ratings.csv" download>Download the ratings sheet</a> · <a href="README.md">Walkthrough and attribution</a></p>
<p class="note">Rate clarity, pumping, transients, stereo image and fatigue. Ties are valid. These research candidates do not establish 3 LU Midnight performance or production acceptance.</p>
<footer>Sintel © Blender Foundation · modified stereo audio · <a href="https://creativecommons.org/licenses/by/3.0/">CC BY 3.0</a></footer>
<script>const player=document.querySelector('#player'),excerpt=document.querySelector('#excerpt'),status=document.querySelector('#status');let label='A',generation=0;
function choose(next,reset=false){const position=reset?0:player.currentTime||0;player.pause();label=next;const token=++generation;document.querySelectorAll('[data-label]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.label===label)));status.textContent=`Excerpt ${Number(excerpt.value)}, option ${label}. Paused.`;player.src=`${excerpt.value}/${label}.flac`;player.onloadedmetadata=()=>{if(token!==generation)return;player.currentTime=Math.min(position,player.duration||45);};player.load();}
document.querySelectorAll('[data-label]').forEach(b=>b.onclick=()=>choose(b.dataset.label));excerpt.onchange=()=>choose('A',true);player.onplay=()=>status.textContent=`Excerpt ${Number(excerpt.value)}, option ${label}. Playing.`;player.onpause=()=>status.textContent=`Excerpt ${Number(excerpt.value)}, option ${label}. Paused.`;player.onerror=()=>status.textContent='Audio could not load. Open the matching FLAC file in Finder, or use the local preview server.';choose('A',true);</script></html>''')
    page = args.output/'index.html'
    page.write_text(page.read_text().replace('${label}.flac`', '${label}.flac?v='+digest(audit/'manifest.json')[:16]+'`'))
    shutil.rmtree(staging)
    (args.output/'INCOMPLETE.txt').unlink()
    (args.output/'READY.txt').write_text('Numerical preparation complete. Owner listening ratings remain pending.\n')
    print('Listening pack ready:', args.output)


if __name__ == '__main__':
    main()
