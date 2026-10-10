import { useEffect, useId, useRef, useState } from "react";
import "./physics-dice.css";

// The upstream module has no TypeScript declarations. Keep its private API
// confined to this adapter; the rest of the app only passes public roll data.
type Engine = any;
export function PhysicsDice({ dice, rollId }: { dice: number[]; rollId?: string }) {
  const id = `dice-${useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  const host = useRef<HTMLDivElement>(null);
  const engine = useRef<Engine>(null);
  const pending = useRef({ dice, rollId });
  pending.current = { dice, rollId };
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  const [settled, setSettled] = useState("");

  useEffect(() => {
    let disposed = false;
    let box: Engine;
    let observer: ResizeObserver | undefined;
    void import("@3d-dice/dice-box-threejs").then(async ({ default: DiceBox }) => {
      if (disposed || !host.current) return;
      box = new DiceBox(`#${id}`, {
        sounds: false, shadows: true, baseScale: 62, strength: 1,
        light_intensity: 1.1, color_spotlight: 0xffffff, theme_material: "plastic",
        theme_customColorset: { name: "triangle-agency-official-style", foreground: "#ffffff", background: "#8e9ba5", outline: "none", edge: "#dce3e6", texture: "none", material: "plastic" },
      });
      // Upstream attaches an anonymous window listener. Use a scoped observer
      // instead, allowing proper React unmount cleanup and panel resizing.
      box.resizeWorld = () => {};
      const makeTexture = box.DiceFactory.createTextMaterial.bind(box.DiceFactory);
      box.DiceFactory.createTextMaterial = (...args: unknown[]) => {
        const original = CanvasRenderingContext2D.prototype.fillText;
        // Each D4 face prints three labels near its vertices. The upstream
        // rotates the canvas for each label, so this corner follows vertex 3
        // consistently on every face and also after predetermined face swaps.
        // Bump-map text remains black. Restore the drawing method synchronously.
        CanvasRenderingContext2D.prototype.fillText = function(text, x, y, maxWidth) {
          const color = this.fillStyle;
          if (String(text).trim() === "3" && color === "#ffffff") {
            const size = this.canvas.width;
            this.save();
            this.fillStyle = "#c92c30";
            this.beginPath();
            this.moveTo(size * .5, -size * .08);
            this.lineTo(size * .28, size * .34);
            this.lineTo(size * .72, size * .34);
            this.closePath();
            this.fill();
            this.restore();
          }
          if (maxWidth === undefined) original.call(this, text, x, y);
          else original.call(this, text, x, y, maxWidth);
          this.fillStyle = color;
        };
        try { return makeTexture(...args); }
        finally { CanvasRenderingContext2D.prototype.fillText = original; }
      };
      await box.initialize();
      if (disposed) { box.renderer.dispose(); return; }
      box.light_amb.color.set("#e9eff5");
      box.light_amb.groundColor.set("#677784");
      engine.current = box;
      observer = new ResizeObserver(() => {
        if (disposed || !host.current) return;
        box.dimensions.set(host.current.clientWidth, host.current.clientHeight);
        box.setDimensions(box.dimensions);
      });
      observer.observe(host.current!);
      setReady(true);
    }).catch(() => { if (!disposed) setFailed(true); });
    return () => {
      disposed = true; observer?.disconnect(); engine.current = null;
      if (!box?.renderer) return;
      box.running = false; box.rolling = false;
      cancelAnimationFrame(box.threadid);
      box.scene.traverse((object: Engine) => {
        object.geometry?.dispose();
        const materials = Array.isArray(object.material) ? object.material : [object.material];
        materials.forEach((material: Engine) => { material?.map?.dispose(); material?.bumpMap?.dispose(); material?.dispose(); });
      });
      box.renderer.dispose(); box.renderer.domElement.remove();
    };
  }, [id]);

  useEffect(() => {
    if (!ready || !engine.current || !rollId) return;
    // The cloud result is authoritative; animations must not generate another roll.
    const box = engine.current;
    const expected = pending.current.dice.join(",");
    setSettled("");
    setFailed(false);
    void box.roll(`6d4@${expected}`).then(() => {
      if (engine.current !== box || pending.current.rollId !== rollId) return;
      const actual = box.diceList.map((die: Engine) => die.getLastValue().value).join(",");
      if (actual !== expected) setFailed(true);
      else setSettled(actual);
    }).catch(() => { if (engine.current === box) setFailed(true); });
  }, [ready, rollId]);

  return <div className="physics-dice-wrap">
    <div ref={host} id={id} className="physics-dice-scene" data-settled-results={settled} role="img" aria-label={rollId ? `六枚四面骰：${dice.join("、")}` : "等待投掷六枚四面骰"} />
    {!ready && !failed && <span className="physics-dice-loading">骰盘准备中…</span>}
    {failed && <span className="physics-dice-loading">立体骰盘暂不可用，投骰结果仍以记录为准</span>}
    {rollId && <div className="physics-dice-values" aria-label="本次各骰结果">{dice.map((value, index) => <span className={value === 3 ? "red-three" : ""} key={index}>{value}</span>)}</div>}
  </div>;
}
