import { useEffect, useRef } from "react";
import "./die3d.css";

type Point = [number, number, number];
// Regular tetrahedron: all six edges have the same length.
const vertices: Point[] = [[0, -1, 0], [-Math.sqrt(2 / 3), 1 / 3, Math.sqrt(2) / 3], [Math.sqrt(2 / 3), 1 / 3, Math.sqrt(2) / 3], [0, 1 / 3, -2 * Math.sqrt(2) / 3]];
const faces = [[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]];

export function Die3D({ value, index, rollId }: { value: number; index: number; rollId?: string }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const element = canvas.current;
    const ctx = element?.getContext("2d");
    if (!element || !ctx) return;
    const resolution = Math.min(window.devicePixelRatio || 1, 2);
    element.width = 180 * resolution;
    element.height = 190 * resolution;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const started = performance.now();
    let frame = 0;
    const numbers = [value, ...[1, 2, 3, 4].filter(n => n !== value)];
    function draw(now: number) {
      if (!ctx) return;
      const progress = !rollId || reduced ? 1 : Math.max(0, Math.min(1, (now - started - index * 45) / 1050));
      const remaining = Math.pow(1 - progress, 3);
      const angleX = -0.32 + remaining * Math.PI * 4;
      const angleY = 0.92 + remaining * Math.PI * (index % 2 ? -4 : 4);
      const angleZ = (index % 2 ? -0.12 : 0.12) + remaining * Math.PI * 2;
      const bounce = Math.abs(Math.sin(progress * Math.PI * 3)) * (1 - progress) * 25;
      const rotated = vertices.map(([x, y, z]): Point => {
        const y1 = y * Math.cos(angleX) - z * Math.sin(angleX);
        const z1 = y * Math.sin(angleX) + z * Math.cos(angleX);
        const x2 = x * Math.cos(angleY) + z1 * Math.sin(angleY);
        const z2 = -x * Math.sin(angleY) + z1 * Math.cos(angleY);
        return [x2 * Math.cos(angleZ) - y1 * Math.sin(angleZ), x2 * Math.sin(angleZ) + y1 * Math.cos(angleZ), z2];
      });
      const project = ([x, y, z]: Point) => {
        const perspective = 4 / (4 - z);
        return [90 + x * 64 * perspective, 105 + y * 64 * perspective - bounce];
      };
      ctx.setTransform(resolution, 0, 0, resolution, 0, 0);
      ctx.clearRect(0, 0, 180, 190);
      const shadow = ctx.createRadialGradient(90, 157, 2, 90, 157, 55);
      shadow.addColorStop(0, "rgba(0,0,0,.45)");
      shadow.addColorStop(1, "rgba(0,0,0,0)");
      ctx.save(); ctx.translate(90, 157); ctx.scale(1, .3); ctx.translate(-90, -157);
      ctx.fillStyle = shadow; ctx.fillRect(30, 100, 120, 114); ctx.restore();
      faces.map((face, faceIndex) => ({ face, faceIndex, depth: face.reduce((s, v) => s + rotated[v][2], 0) / 3 }))
        .sort((a, b) => a.depth - b.depth).forEach(({ face, faceIndex, depth }) => {
          const points = face.map(v => project(rotated[v]));
          const [a, b, c] = points;
          // Back-face culling in screen coordinates.
          if ((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) >= 0) return;
          ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.lineTo(c[0], c[1]); ctx.closePath();
          const light = Math.round(185 + depth * 58);
          const gradient = ctx.createLinearGradient(a[0], a[1], c[0], c[1]);
          gradient.addColorStop(0, `rgb(${Math.min(255, light + 43)},${Math.min(255, light + 36)},${Math.min(255, light + 22)})`);
          gradient.addColorStop(1, `rgb(${light},${light - 7},${light - 20})`);
          ctx.fillStyle = gradient; ctx.fill();
          ctx.strokeStyle = "#817667"; ctx.lineWidth = 1.4; ctx.lineJoin = "round"; ctx.stroke();
          // Place the inscription in the face's local basis so it rotates with the mesh.
          ctx.save();
          const cx = (a[0] + b[0] + c[0]) / 3, cy = (a[1] + b[1] + c[1]) / 3;
          ctx.transform((c[0] - b[0]) / 112, (c[1] - b[1]) / 112, (b[0] + c[0] - 2 * a[0]) / 190, (b[1] + c[1] - 2 * a[1]) / 190, cx, cy);
          ctx.font = "bold 35px Georgia, serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle";
          ctx.fillStyle = numbers[faceIndex] === 3 ? "#bc302c" : "#39352f";
          ctx.fillText(String(numbers[faceIndex]), 0, 1);
          ctx.restore();
        });
      if (progress < 1) frame = requestAnimationFrame(draw);
    }
    frame = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(frame);
  }, [value, index, rollId]);
  return <canvas ref={canvas} className="die-model" role="img" aria-label={`立体四面骰，结果 ${value}`} />;
}
