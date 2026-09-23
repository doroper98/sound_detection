// Offline evidence audit only. No app changes or iPhone measurements.
import { writeFileSync } from 'node:fs';
import { measureFrame, localize, distance } from '../packages/localization/dist/index.js';

const fs = 48000, n = 4096;
const pair = [[-0.06, 0, 0], [0.06, 0, 0]];
function rng(seed) {
  let state = seed >>> 0;
  return () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 4294967296; };
}
function excitation(seed, low, high) {
  const random = rng(seed);
  const waves = Array.from({length: 64}, () => ({f: low + random() * (high-low), p: random() * 2*Math.PI}));
  return t => waves.reduce((s, w) => s + Math.sin(2*Math.PI*w.f*t/fs+w.p), 0) * 0.003;
}
// Transliteration of the build-9 Swift analyzer's lag and acceptance calculation.
// It is not execution of the Swift binary. Fixtures are finite, active, unclipped.
function nativeLag(left, right) {
  const mean = a => a.reduce((s,v)=>s+v,0)/a.length;
  const ml=mean(left), mr=mean(right);
  const x=Array.from(left,v=>v-ml), y=Array.from(right,v=>v-mr);
  let xx=0, yy=0, xy=0;
  for(let i=0;i<n;i++) {xx+=x[i]*x[i];yy+=y[i]*y[i];xy+=x[i]*y[i];}
  if(Math.sqrt(Math.max(0,1-xy*xy/(xx*yy)))<1e-5) return {status:'duplicate'};
  const scores=[];
  for(let lag=-48;lag<=48;lag++) {
    let a=0,b=0,c=0;
    for(let i=Math.max(0,-lag);i<Math.min(n,n-lag);i++) {a+=x[i]*y[i+lag];b+=x[i]*x[i];c+=y[i+lag]*y[i+lag];}
    scores.push({lag,score:Math.min(1,Math.abs(a/Math.sqrt(b*c)))});
  }
  const best=scores.reduce((a,b)=>b.score>a.score?b:a);
  const margin=best.score-Math.max(...scores.filter(v=>Math.abs(v.lag-best.lag)>2).map(v=>v.score));
  const status=best.score<0.35?'weakCorrelation':Math.abs(best.lag)===48?'searchBoundary':margin<0.08?'ambiguous':'candidate';
  return {status,lag:best.lag,margin,peak:best.score};
}
function gcc(left,right,positions=pair) {
  const m=measureFrame({channels:[left,right],sampleRate:fs,microphonePositions:positions,synchronized:true});
  return {lag:-m.observations[0].delay*fs, peakRatio:m.peakRatio, observation:m.observations[0]};
}
const lagCases=[];
for(const [name,low,high,echo] of [
  ['broadband_direct',300,10000,false],
  ['low_frequency_direct',100,800,false],
  ['broadband_with_stronger_different_echo',300,10000,true]
]) {
  const rows=[];
  for(let seed=1;seed<=12;seed++) {
    const s=excitation(seed,low,high), lag=5.35;
    const left=Float32Array.from({length:n},(_,i)=>s(i)+(echo?1.4*s(i-70):0));
    const right=Float32Array.from({length:n},(_,i)=>s(i-lag)+(echo?1.4*s(i-80):0));
    const native=nativeLag(left,right), phat=gcc(left,right);
    rows.push({seed,trueDirectLagSamples:lag,native,gcc:{lag:phat.lag,peakRatio:phat.peakRatio},
      nativeAbsoluteErrorSamples:Math.abs(native.lag-lag),gccAbsoluteErrorSamples:Math.abs(phat.lag-lag)});
  }
  const accepted=rows.filter(r=>r.native.status==='candidate');
  lagCases.push({name,seeds:rows.length,nativeAccepted:accepted.length,
    nativeAcceptedMeanAbsoluteErrorSamples:accepted.length?accepted.reduce((s,r)=>s+r.nativeAbsoluteErrorSamples,0)/accepted.length:null,
    gccMeanAbsoluteErrorSamples:rows.reduce((s,r)=>s+r.gccAbsoluteErrorSamples,0)/rows.length,rows});
}
// Counterexample: a fixed digital inter-channel delay is measurable but contains
// no direction information. This does NOT assert that Apple uses this process.
const skewRows=[-25,0,25].map(angle=>{
  const s=excitation(444,300,10000);
  const left=Float32Array.from({length:n},(_,i)=>s(i));
  const right=Float32Array.from({length:n},(_,i)=>s(i-5));
  return {declaredAngle:angle,native:nativeLag(left,right),gccLag:gcc(left,right).lag};
});

// Real engine, synthetic PCM. Ground truth used ONLY by generator and scorer.
const source=[-0.87,1.37,-1.43];
const poses=[
  [[0,1.1,1.4],[1,0,0]], [[-1.2,0.7,0.8],[0.8,0.3,0.4]],
  [[1.2,1.8,0.7],[0.8,-0.4,-0.3]], [[-1.3,1.9,-0.3],[0.6,0.6,0.5]],
  [[0.6,0.6,-0.2],[0.6,-0.6,0.5]], [[0.5,2.1,-2.2],[0.4,0.7,0.5]],
  [[-1.7,0.6,-2],[0.8,-0.2,0.5]], [[0.1,1.4,-2.4],[0.9,0.3,0.2]]
];
function observation([origin,axis],seed) {
  const length=Math.hypot(...axis);
  const positions=[-1,1].map(sign=>origin.map((v,i)=>v+sign*0.06*axis[i]/length));
  const offsets=positions.map(p=>distance(source,p)/343*fs);
  const s=excitation(seed,300,10000);
  const pcm=positions.map((p,j)=>Float32Array.from({length:n},(_,i)=>s(i-offsets[j])/Math.max(0.1,distance(source,p))));
  return gcc(...pcm,positions).observation;
}
const volume={min:[-2.5,0.2,-3],max:[2.5,2.6,2],step:0.1};
const first=observation(poses[0],701);
const spatialCases=[
  ['single_pose',[first]],
  ['eight_frames_same_pose',Array.from({length:8},()=>({...first}))],
  ['eight_different_positions_and_axes',poses.map((p,i)=>observation(p,701+i))]
].map(([name,observations])=>{
  const solution=localize(observations,volume);
  return {name,observations:observations.length,solution,errorMeters:distance(source,solution.position)};
});
const report={
  evidenceType:'synthetic_counterexamples_and_existing_engine_experiment_NOT_iPhone_validation',
  sourceRevision:'92b8c5008b1ace28b12428f8d9db9800a1feb419',
  sampleRate:fs,samplesPerFrame:n,seedsPerLagCase:12,
  assumptions:['One known synthetic waveform; no device DSP, clock error, pose error, or sensor noise.',
    'Known virtual 12 cm spacing; no claim about iPhone microphone geometry.',
    'Spatial source is off the search grid; known diverse poses span several meters.',
    'GCC engine always returns a peak; its returned number is not an acceptance or physical-validity test.',
    'Swift method transliterated into JS for comparison; production Swift binary not run.',
    'Stronger-echo fixture intentionally demonstrates a possible failure, not typical-room statistics.'],
  lagCases,skewCounterexample:skewRows,spatialCases,
  freeFieldLevelCounterexample:{
    virtualSpacingMeters:0.12,sourceDistanceMeters:1,angleDegrees:25,
    absoluteDifferenceAt25DegreesDb:20*Math.log10(
      Math.hypot(Math.sin(25*Math.PI/180)+0.06,Math.cos(25*Math.PI/180))/
      Math.hypot(Math.sin(25*Math.PI/180)-0.06,Math.cos(25*Math.PI/180))),
    build9MinimumLevelSlopeDbPerDegree:0.04,
    note:'Inverse-distance attenuation of virtual omnidirectional sensors only, NOT an iPhone response model.'
  },
  calibrationGateCounterexample:{hypotheticalRepeatableLagSlopeSamplesPerDegree:0.1,
    build9MinimumLagSlopeSamplesPerDegree:0.12,
    implication:'A repeatable, informative relation can be rejected by the heuristic slope gate. This does not demonstrate that the actual iPhone has such a relation.'}
};
writeFileSync(new URL('../docs/reports/2026-09-23-localization-feasibility-synthetic.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({lagCases:lagCases.map(({rows,...summary})=>summary),skewCounterexample:skewRows,spatialCases},null,2));
