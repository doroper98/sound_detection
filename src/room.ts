import * as THREE from 'three';

export function createRoom() {
  const root = new THREE.Group();
  const surfaces: THREE.Mesh[] = [];
  const box = (size: number[], position: number[], color: string, rotation = 0) => {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(...size as [number, number, number]), new THREE.MeshStandardMaterial({ color, roughness: 0.82 }));
    mesh.position.set(...position as [number, number, number]); mesh.rotation.y = rotation;
    mesh.castShadow = true; mesh.receiveShadow = true;
    root.add(mesh); surfaces.push(mesh); return mesh;
  };
  box([8.2, 0.18, 7.2], [0, -0.11, 0], '#d7d2c8');
  box([8, 3.2, 0.12], [0, 1.6, -3.5], '#e9e7df');
  box([0.12, 3.2, 7], [-4, 1.6, 0], '#dedfd8');
  // Floorboards, rug, and a quiet interior give depth cues in both views.
  for (let x = -3.8; x < 4; x += 0.4) box([0.012, 0.006, 7], [x, -0.012, 0], '#bdb8ae');
  box([4.2, 0.025, 3.1], [-0.35, 0.02, -0.4], '#b3bdba');
  for (let x = -2.35; x < 1.7; x += 0.15) box([0.009, 0.002, 3], [x, 0.034, -0.4], '#c5ccca');
  box([3.05, 0.48, 1.03], [-1.4, 0.49, -2.5], '#738e83');
  box([3.05, 0.64, 0.24], [-1.4, 0.94, -2.94], '#647e73');
  for (const x of [-2.78, -0.02]) box([0.3, 0.55, 1.14], [x, 0.8, -2.5], '#708a7e');
  for (const x of [-2.1, -0.75]) {
    box([1.23, 0.16, 0.84], [x, 0.81, -2.43], '#88a093');
    box([0.54, 0.5, 0.15], [x, 1.08, -2.77], '#c3c8b2', 0.14);
  }
  box([1.75, 0.12, 0.85], [-1.1, 0.57, -0.65], '#b98e64');
  for (const x of [-1.78, -0.42]) for (const z of [-0.95, -0.35]) box([0.09, 0.53, 0.09], [x, 0.27, z], '#705c48');
  box([0.38, 0.035, 0.28], [-1.43, 0.66, -0.6], '#ede8db', 0.12);
  box([0.3, 0.025, 0.25], [-1.4, 0.69, -0.59], '#47776f', -0.12);
  box([0.85, 0.12, 0.8], [2.35, 0.68, -1.8], '#b5a07f', -0.2);
  box([0.85, 0.65, 0.15], [2.43, 1.02, -2.15], '#b5a07f', -0.2);
  for (const x of [2.05, 2.68]) for (const z of [-1.52, -2.04]) box([0.07, 0.64, 0.07], [x, 0.32, z], '#675c4d');
  box([1.55, 1.45, 0.055], [-1.45, 2.25, -3.41], '#ac987b');
  box([1.4, 1.3, 0.025], [-1.45, 2.25, -3.37], '#f3f0e5');
  box([0.43, 0.64, 0.02], [-1.67, 2.26, -3.35], '#bb765a', 0.1);
  box([0.47, 0.36, 0.02], [-1.18, 2.08, -3.34], '#789184');
  // Window on left wall.
  box([0.08, 1.9, 2.3], [-3.89, 2.04, -0.75], '#f4f3e8');
  box([0.1, 1.68, 2.06], [-3.83, 2.04, -0.75], '#b4cdd0');
  box([0.12, 1.72, 0.045], [-3.76, 2.04, -0.75], '#f5f4ea');
  box([0.12, 0.045, 2.08], [-3.76, 2.04, -0.75], '#f5f4ea');
  const pot = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.22, 0.47, 20), new THREE.MeshStandardMaterial({ color: '#b49b7f' }));
  pot.position.set(3.16, 0.24, -2.7); pot.castShadow = true; root.add(pot); surfaces.push(pot);
  for (let i = 0; i < 9; i++) {
    const leaf = new THREE.Mesh(new THREE.SphereGeometry(1, 12, 10), new THREE.MeshStandardMaterial({ color: i % 2 ? '#4b7860' : '#648970' }));
    leaf.scale.set(0.15, 0.55, 0.22); leaf.rotation.z = Math.sin(i * 2.4) * 0.75;
    leaf.position.set(3.16 + Math.sin(i * 2.4) * 0.25, 0.75 + (i % 3) * 0.2, -2.7 + Math.cos(i * 2.4) * 0.25);
    root.add(leaf); surfaces.push(leaf);
  }
  box([0.08, 1.95, 0.08], [-3.23, 0.98, -2.73], '#595e55');
  const shade = new THREE.Mesh(new THREE.ConeGeometry(0.4, 0.42, 24, 1, true), new THREE.MeshStandardMaterial({ color: '#e9dcc0', side: THREE.DoubleSide }));
  shade.position.set(-3.23, 1.94, -2.73); root.add(shade); surfaces.push(shade);
  root.updateMatrixWorld(true);
  return { root, surfaces };
}

export function lightScene(scene: THREE.Scene) {
  scene.add(new THREE.HemisphereLight('#ffffff', '#9d9f92', 2.7));
  const sun = new THREE.DirectionalLight('#fff5e1', 3.2);
  sun.position.set(-2, 8, 5); sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  Object.assign(sun.shadow.camera, { left: -7, right: 7, top: 7, bottom: -7, near: 0.1, far: 25 });
  sun.shadow.bias = -0.001; sun.shadow.normalBias = 0.03;
  scene.add(sun);
}

export function disposeScene(scene: THREE.Scene) {
  scene.traverse(object => {
    if (object instanceof THREE.Mesh || object instanceof THREE.Line) {
      object.geometry.dispose();
      const materials = Array.isArray(object.material) ? object.material : [object.material];
      materials.forEach(material => material.dispose());
    }
  });
}
