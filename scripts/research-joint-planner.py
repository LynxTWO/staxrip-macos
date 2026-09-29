#!/usr/bin/env python3
"""Unaccepted local mastering research, never an app renderer or publication gate.

Tested with NumPy 2.0.2 and SciPy 1.13.1 in a private Python environment.
With no arguments, run analytic-gradient checks. Optional --snapshot consumes the
local diagnostic exporter output and requires a new --output-dir. The bounded
model is known to miss the licensed-film range requests. See MASTERING-M1.md.
"""
import argparse
from pathlib import Path
import json, sys, numpy as np
from scipy.optimize import minimize
K = np.log(10)/10

def objective(g, e, target, width, selection=None):
    x = e*np.exp(K*(g[:-1]+g[1:])/2)
    n = len(x)
    prefix = np.r_[0., np.cumsum(x), np.repeat(np.sum(x),75)]
    ends = np.arange(20,n+1,5); starts = ends-20
    sums = np.maximum(1e-30,prefix[ends]-prefix[starts])
    levels = -.691+10*np.log10(sums/20)
    absolute = levels > -70
    gate = max(-70, -.691+10*np.log10(np.mean(sums[absolute])/20)-10)
    chosen = levels > gate if selection is None else selection[0]
    integrated = -.691+10*np.log10(np.mean(sums[chosen])/20)
    weights = np.zeros(n+76)
    coeff = 20*(integrated-target)/np.sum(sums[chosen])
    np.add.at(weights,starts[chosen],coeff); np.add.at(weights,ends[chosen],-coeff)
    grad = x*np.cumsum(weights)[:n]
    se = np.arange(150,n+76,5); ss = se-150
    sums = np.maximum(1e-30,prefix[se]-prefix[ss])
    levels = -.691+10*np.log10(sums/150)
    absolute = levels > -70
    gate = max(-70, -.691+10*np.log10(np.mean(sums[absolute])/150)-20)
    order = np.flatnonzero(levels > gate)
    order = order[np.argsort(levels[order])]
    lo = int((len(order)-1)*.10+.5); hi = int((len(order)-1)*.95+.5)
    central = order[lo:hi+1] if selection is None else selection[1]
    upper = target+1; lower = upper-width
    errors = levels[central]-np.clip(levels[central],lower,upper)
    weights = np.zeros(n+76)
    coeff = 2*errors/(len(central)*sums[central])
    np.add.at(weights,ss[central],coeff); np.add.at(weights,se[central],-coeff)
    grad += x*np.cumsum(weights)[:n]
    out = np.zeros(n+1); out[:-1] += grad/2; out[1:] += grad/2
    differences = np.diff(g)
    out[:-1] -= .2*differences/n; out[1:] += .2*differences/n
    value = 10*(integrated-target)**2+np.mean(errors**2)+.1*np.mean(differences**2)
    return value, out, dict(I=integrated,LRA=levels[order[hi]]-levels[order[lo]],low=levels[order[lo]],high=levels[order[hi]],gate=gate), (chosen,central)

def transform(raw, holds, sigma):
    positions=np.arange(-25,26)*.02
    kernel=np.exp(-.5*(positions/sigma)**2); kernel/=sum(kernel)
    filtered=np.convolve(np.pad(raw,(25,25),mode='edge'),kernel,mode='valid')
    owners=np.arange(len(raw))
    rise=.12 if sigma==.2 else .48
    fall=.48 if sigma==.2 else 1.2
    for i in range(1,len(raw)):
        upper=filtered[i-1]+(0 if holds[i] else rise)
        lower=filtered[i-1]-fall
        if filtered[i]>upper:
            filtered[i]=upper; owners[i]=owners[i-1]
        elif filtered[i]<lower:
            filtered[i]=lower; owners[i]=owners[i-1]
    filtered=np.clip(filtered,-36,12)
    return filtered,owners,kernel

def transformed(raw,e,target,width,holds,sigma,selection=None):
    gain,owners,kernel=transform(raw,holds,sigma)
    value,gradient,metrics,selected=objective(gain,e,target,width,selection)
    gradient=np.bincount(owners,weights=gradient,minlength=len(raw))
    padded=np.convolve(gradient,kernel,mode='full')
    result=padded[25:25+len(raw)].copy()
    result[0]+=sum(padded[:25]); result[-1]+=sum(padded[25+len(raw):])
    return value,result,metrics,selected

def check():
    rng = np.random.default_rng(54)
    e = np.exp(rng.normal(-6,1,600)); g = rng.normal(0,.5,601)
    v,d,_,_ = objective(g,e,-23,3)
    error=0
    for i in (0,1,17,100,301,599,600):
        a=g.copy(); b=g.copy(); a[i]+=1e-5; b[i]-=1e-5
        actual=(objective(a,e,-23,3)[0]-objective(b,e,-23,3)[0])/2e-5
        error=max(error,abs(actual-d[i]))
    assert error<1e-5,error
    print('GRADIENT CHECK',error,flush=True)
    holds=np.zeros(601,dtype=bool); holds[100:180]=True; holds[410:600]=True
    v,d,_,_=transformed(g,e,-23,3,holds,.08)
    error=0
    for i in (0,1,17,100,301,599,600):
        a=g.copy(); b=g.copy(); a[i]+=1e-5; b[i]-=1e-5
        actual=(transformed(a,e,-23,3,holds,.08)[0]-transformed(b,e,-23,3,holds,.08)[0])/2e-5
        error=max(error,abs(actual-d[i]))
    assert error<1e-5,error
    print('TRANSFORMED GRADIENT CHECK',error,flush=True)
    raw=-12+10*np.sin(np.arange(601)*.25)
    for sigma in (.2,.08):
        filtered,owners,_=transform(raw,holds,sigma)
        rise,fall=(.12,.48) if sigma==.2 else (.48,1.2)
        assert np.max(np.diff(filtered))<=rise+1e-10
        assert np.min(np.diff(filtered))>=-fall-1e-10
        assert np.max(np.diff(filtered)[holds[1:]])<=1e-10
        assert np.any((owners!=np.arange(601)) & ~holds)
        value,gradient,_,_=transformed(raw,e,-23,3,holds,sigma)
        error=0
        for i in (0,1,17,100,301,599,600):
            a=raw.copy(); b=raw.copy(); a[i]+=1e-5; b[i]-=1e-5
            actual=(transformed(a,e,-23,3,holds,sigma)[0]-transformed(b,e,-23,3,holds,sigma)[0])/2e-5
            error=max(error,abs(actual-gradient[i]))
        assert error<1e-5,error
        print('ACTIVE SLOPE CHECK',sigma,error,flush=True)


parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--snapshot',type=Path)
parser.add_argument('--output-dir',type=Path)
args=parser.parse_args()
check()
if args.snapshot:
    if not args.output_dir: parser.error('--snapshot requires --output-dir')
    s=json.loads(args.snapshot.read_text()); e=np.array(s['energies']); n=len(e)
    if n < 150 or n > 720000 or not np.all(np.isfinite(e)) or np.any(e<0):
        raise ValueError('Unsupported research timeline')
    args.output_dir.mkdir(mode=0o700)

    for mode,target,lra in [('smart',-23,11),('night',-30,3)]:
        trace=s['trace']; base=target-s['sourceIntegrated']; floor=max(-55,s['sourceIntegrated']-25)
        holds=np.array([(trace[min(i+9,len(trace)-1)].get('momentary') or -100)<floor for i in range(n+1)])
        lower=np.full(n+1,-36.); upper=np.full(n+1,12.)
        lower[holds]=base; upper[holds]=base
        initial=np.full(n+1,base)
        sigma=.2 if mode=="smart" else .08
        def evaluate(g,selection=None): return transformed(g,e,target,max(.5,lra-.5),holds,sigma,selection)
        for iteration in range(10):
            selected=evaluate(initial)[3]
            result=minimize(lambda g: evaluate(g,selected)[:2],initial,jac=True,method='L-BFGS-B',bounds=list(zip(lower,upper)),options={'maxiter':100,'ftol':1e-10,'gtol':1e-7,'maxcor':10})
            initial=result.x
            print('OUTER',mode,iteration,result.message,evaluate(initial)[2],flush=True)
        print('RESULT',mode,evaluate(initial)[2],flush=True)
        with (args.output_dir/(mode+'-envelope.json')).open('x') as stream:
            json.dump(transform(initial,holds,sigma)[0].tolist(),stream,allow_nan=False)
        with (args.output_dir/(mode+'-prediction.json')).open('x') as stream:
            json.dump(evaluate(initial)[2],stream,allow_nan=False)
