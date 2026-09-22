import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { clamp, distance, heatColor, type Observation, type Receiver, type Source, type Vec3 } from '../acoustics';
import { rayLikelihood } from '../../packages/localization/src/index';
import { createRoom, disposeScene, lightScene } from '../room';
import { heatIntensity } from '../heatmap';

type Props = { source: Source | null; candidate: Vec3 | null; receiver: Receiver; observations: Observation[]; levelDbfs: number; mode: 'pressure' | 'estimate'; opacity: number; heatmap: boolean; onLook: (yaw: number, pitch: number) => void };

export default function PhoneView(props: Props) {
  const host = useRef<HTMLDivElement>(null); const heat = useRef<HTMLCanvasElement>(null);
  const marker = useRef<HTMLDivElement>(null);
  const current = useRef(props); current.current = props;
  const update = useRef<() => void>(() => {}); const [error, setError] = useState(false);
  useEffect(() => { update.current(); }, [props.source, props.candidate, props.receiver, props.observations, props.levelDbfs, props.mode, props.opacity, props.heatmap]);
  useEffect(() => {
    const container = host.current!;
    let renderer: THREE.WebGLRenderer;
    try { renderer = new THREE.WebGLRenderer({ antialias: true }); } catch { setError(true); return; }
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2)); renderer.setClearColor('#b5c5ca');
    renderer.domElement.className = 'phone-world'; container.prepend(renderer.domElement);
    const scene = new THREE.Scene(); lightScene(scene);
    const { root } = createRoom(); scene.add(root);
    const camera = new THREE.PerspectiveCamera(65, 1, 0.04, 40);
    const raycaster = new THREE.Raycaster(); const pointer = new THREE.Vector2();
    const context = heat.current!.getContext('2d')!;
    const width = 72; const height = 126; heat.current!.width = width; heat.current!.height = height;
    const ranges = [0.3, 0.5, 0.8, 1.2, 1.8, 2.5, 3.5, 5, 7, 10];
    let pending = 0;
    const draw = () => {
      const { source, candidate, receiver, observations, levelDbfs, mode, opacity, heatmap } = current.current;
      camera.position.set(...receiver.position);
      camera.lookAt(camera.position.clone().add(new THREE.Vector3(Math.sin(receiver.yaw) * Math.cos(receiver.pitch), Math.sin(receiver.pitch), -Math.cos(receiver.yaw) * Math.cos(receiver.pitch))));
      camera.updateMatrixWorld(); renderer.render(scene, camera);
      context.clearRect(0, 0, width, height);
      const target = source?.position ?? candidate;
      const samplingRanges = candidate ? [...ranges, distance(receiver.position, candidate)] : ranges;
      const projected = target ? new THREE.Vector3(...target).project(camera) : null;
      const targetVisible = projected && projected.z > -1 && projected.z < 1 && Math.abs(projected.x) < 1 && Math.abs(projected.y) < 1;
      marker.current!.style.display = targetVisible && heatmap ? 'flex' : 'none';
      if (projected) { marker.current!.style.left = `${(projected.x + 1) * 50}%`; marker.current!.style.top = `${(1 - projected.y) * 50}%`; }
      if (!heatmap || (mode === 'estimate' && receiver.count === 1)) return;
      const data = context.createImageData(width, height);
      for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
        pointer.set((x + 0.5) / width * 2 - 1, 1 - (y + 0.5) / height * 2);
        raycaster.setFromCamera(pointer, camera);
        let value = 0;
        if (mode === 'pressure' && projected && projected.z > -1 && projected.z < 1) {
          // Explicit ground-truth reference marker. Never used in inference mode.
          const dx = x + 0.5 - (projected.x + 1) * width / 2;
          const dy = y + 0.5 - (1 - projected.y) * height / 2;
          value = Math.exp(-(dx * dx + dy * dy) / (2 * 7 ** 2));
        } else if (mode === 'estimate') {
          value = rayLikelihood(receiver.position, raycaster.ray.direction.toArray() as Vec3, observations, samplingRanges);
        }
        const intensity = heatIntensity(value, levelDbfs);
        if (intensity <= 0) continue;
        const offset = (y * width + x) * 4;
        const color = heatColor(intensity);
        data.data[offset] = color[0]; data.data[offset + 1] = color[1]; data.data[offset + 2] = color[2];
        data.data[offset + 3] = Math.round(opacity * 255 * Math.sqrt(intensity));
      }
      context.putImageData(data, 0, 0);
    };
    update.current = () => { cancelAnimationFrame(pending); pending = requestAnimationFrame(draw); };
    const resize = new ResizeObserver(() => {
      const { width: w, height: h } = container.getBoundingClientRect();
      if (w < 1 || h < 1) return;
      renderer.setSize(w, h);
      camera.aspect = w / h; camera.updateProjectionMatrix(); update.current();
    }); resize.observe(container);
    let drag: { x: number; y: number; yaw: number; pitch: number } | null = null;
    const onDown = (event: PointerEvent) => { container.setPointerCapture(event.pointerId); drag = { x: event.clientX, y: event.clientY, yaw: current.current.receiver.yaw, pitch: current.current.receiver.pitch }; };
    const onMove = (event: PointerEvent) => { if (drag) current.current.onLook(drag.yaw - (event.clientX - drag.x) * 0.006, clamp(drag.pitch + (event.clientY - drag.y) * 0.006, -1.2, 1.2)); };
    const onUp = () => { drag = null; };
    const onKey = (event: KeyboardEvent) => {
      const steps: Record<string, [number, number]> = { ArrowLeft: [-0.1, 0], ArrowRight: [0.1, 0], ArrowUp: [0, 0.1], ArrowDown: [0, -0.1] };
      const step = steps[event.key]; if (!step) return; event.preventDefault();
      current.current.onLook(current.current.receiver.yaw + step[0], clamp(current.current.receiver.pitch + step[1], -1.2, 1.2));
    };
    container.addEventListener('pointerdown', onDown); container.addEventListener('pointermove', onMove);
    container.addEventListener('pointerup', onUp); container.addEventListener('pointercancel', onUp); container.addEventListener('keydown', onKey);
    return () => {
      cancelAnimationFrame(pending); resize.disconnect(); update.current = () => {};
      container.removeEventListener('pointerdown', onDown); container.removeEventListener('pointermove', onMove);
      container.removeEventListener('pointerup', onUp); container.removeEventListener('pointercancel', onUp); container.removeEventListener('keydown', onKey);
      disposeScene(scene); renderer.dispose(); renderer.domElement.remove();
    };
  }, []);
  return <div ref={host} className="phone-viewport" data-testid="phone-viewport" tabIndex={0} role="application" aria-label="휴대폰 시야. 드래그 또는 방향키로 둘러보기">
    <canvas ref={heat} className="phone-heat" data-testid="heatmap-canvas" />
    <div ref={marker} className="acoustic-target"><i /><span>{props.mode === 'pressure' ? '정답 음원' : '추정 후보'}</span></div>
    {error && <div className="canvas-error">WebGL을 사용할 수 없습니다.</div>}
  </div>;
}
