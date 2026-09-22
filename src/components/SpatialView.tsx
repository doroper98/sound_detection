import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { clamp, microphones, type Receiver, type Source, type Vec3 } from '../acoustics';
import { createRoom, disposeScene, lightScene } from '../room';

type Props = { source: Source; receiver: Receiver; playing: boolean; placement: 'source' | 'receiver' | 'orbit'; resetKey: number; onPlace: (point: Vec3) => void };

export default function SpatialView(props: Props) {
  const host = useRef<HTMLDivElement>(null);
  const latest = useRef(props); latest.current = props;
  const [error, setError] = useState(false);
  const reset = useRef<() => void>(() => {});
  useEffect(() => { reset.current(); }, [props.resetKey]);

  useEffect(() => {
    const container = host.current!;
    let renderer: THREE.WebGLRenderer;
    try { renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true }); } catch { setError(true); return; }
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFShadowMap;
    renderer.setClearColor('#eef1f1'); container.appendChild(renderer.domElement);
    renderer.domElement.setAttribute('aria-label', '3D 실내 공간. 클릭하여 배치하고 드래그하여 회전');
    renderer.domElement.setAttribute('data-testid', 'spatial-canvas');
    const scene = new THREE.Scene(); lightScene(scene);
    const { root, surfaces } = createRoom(); scene.add(root);
    const camera = new THREE.PerspectiveCamera(38, 1, 0.1, 70);
    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true; controls.minDistance = 7; controls.maxDistance = 23;
    controls.maxPolarAngle = Math.PI / 2.1; controls.target.set(0, 0.6, -0.3);
    reset.current = () => { camera.position.set(10, 10.6, 13); controls.target.set(0, 0.6, -0.3); controls.update(); };
    reset.current();
    const sourceMarker = new THREE.Mesh(new THREE.SphereGeometry(0.13, 24, 16), new THREE.MeshStandardMaterial({ color: '#ff8057', emissive: '#ff522c', emissiveIntensity: 0.8 }));
    scene.add(sourceMarker);
    const rings = Array.from({ length: 3 }, () => {
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.4, 0.012, 8, 70), new THREE.MeshBasicMaterial({ color: '#f98a64', transparent: true, opacity: 0.6 }));
      ring.rotation.x = Math.PI / 2; scene.add(ring); return ring;
    });
    const stem = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3(0, 1, 0)]), new THREE.LineDashedMaterial({ color: '#dc7958', dashSize: 0.08, gapSize: 0.06 }));
    stem.computeLineDistances(); scene.add(stem);
    const phone = new THREE.Mesh(new THREE.BoxGeometry(0.23, 0.43, 0.045), new THREE.MeshStandardMaterial({ color: '#244f49', metalness: 0.25, roughness: 0.4 }));
    scene.add(phone);
    const pairMarkers = [0, 1].map(() => {
      const marker = new THREE.Mesh(new THREE.SphereGeometry(0.055, 12, 10), new THREE.MeshBasicMaterial({ color: '#0ea98a' }));
      scene.add(marker); return marker;
    });
    const baseline = new THREE.Line(new THREE.BufferGeometry(), new THREE.LineBasicMaterial({ color: '#0aa184' })); scene.add(baseline);
    const cone = new THREE.Mesh(new THREE.ConeGeometry(0.8, 1.65, 4, 1, true), new THREE.MeshBasicMaterial({ color: '#3cbeac', transparent: true, opacity: 0.08, side: THREE.DoubleSide, depthWrite: false }));
    scene.add(cone);
    const raycaster = new THREE.Raycaster(); const pointer = new THREE.Vector2();
    let down = { x: 0, y: 0 };
    const onDown = (event: PointerEvent) => { down = { x: event.clientX, y: event.clientY }; };
    const onUp = (event: PointerEvent) => {
      if (Math.hypot(event.clientX - down.x, event.clientY - down.y) > 6 || latest.current.placement === 'orbit' || event.button !== 0) return;
      const rect = renderer.domElement.getBoundingClientRect();
      pointer.set((event.clientX - rect.left) / rect.width * 2 - 1, -((event.clientY - rect.top) / rect.height) * 2 + 1);
      raycaster.setFromCamera(pointer, camera);
      const hit = raycaster.intersectObjects(surfaces, false)[0];
      if (hit) latest.current.onPlace([clamp(hit.point.x, -3.7, 3.7), clamp(hit.point.y + 0.12, 0.1, 3.1), clamp(hit.point.z, -3.2, 3.2)]);
    };
    renderer.domElement.addEventListener('pointerdown', onDown); renderer.domElement.addEventListener('pointerup', onUp);
    const resize = new ResizeObserver(() => {
      const { width, height } = container.getBoundingClientRect();
      renderer.setSize(width, height); camera.aspect = width / height; camera.updateProjectionMatrix();
    }); resize.observe(container);
    let frame = 0; let elapsed = 0; let lastTime = 0;
    const animate = (time: number) => {
      const { source, receiver, playing } = latest.current;
      if (playing) elapsed += Math.min(time - lastTime, 50) / 1000;
      lastTime = time;
      sourceMarker.position.set(...source.position);
      stem.position.set(source.position[0], 0.06, source.position[2]); stem.scale.y = Math.max(0.02, source.position[1] - 0.06);
      rings.forEach((ring, index) => {
        const phase = (elapsed * 0.45 + index / 3) % 1;
        ring.position.copy(sourceMarker.position); ring.scale.setScalar(0.5 + phase * 4);
        ring.material.opacity = (1 - phase) * 0.45;
      });
      phone.position.set(...receiver.position); phone.rotation.set(0, -receiver.yaw, 0);
      const pair = microphones(receiver);
      pairMarkers.forEach((marker, index) => { marker.position.set(...pair[index]); marker.visible = receiver.count === 2; });
      baseline.geometry.setFromPoints(pair.map(position => new THREE.Vector3(...position))); baseline.visible = receiver.count === 2;
      const direction = new THREE.Vector3(Math.sin(receiver.yaw) * Math.cos(receiver.pitch), Math.sin(receiver.pitch), -Math.cos(receiver.yaw) * Math.cos(receiver.pitch));
      cone.position.copy(phone.position).addScaledVector(direction, 0.83);
      cone.quaternion.setFromUnitVectors(new THREE.Vector3(0, -1, 0), direction);
      controls.update(); renderer.render(scene, camera); frame = requestAnimationFrame(animate);
    }; frame = requestAnimationFrame(animate);
    return () => {
      cancelAnimationFrame(frame); resize.disconnect(); controls.dispose();
      renderer.domElement.removeEventListener('pointerdown', onDown); renderer.domElement.removeEventListener('pointerup', onUp);
      disposeScene(scene); renderer.dispose(); renderer.domElement.remove();
    };
  }, []);
  return <div ref={host} className="spatial-canvas">{error && <div className="canvas-error">3D 화면을 열 수 없습니다. 브라우저의 하드웨어 가속(WebGL)을 켜 주세요.</div>}</div>;
}
