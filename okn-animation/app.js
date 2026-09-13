const canvas = document.querySelector("#oknCanvas");
const frame = document.querySelector("[data-frame]");
const context = canvas.getContext("2d");

const controls = {
  speed: document.querySelector("#speed"),
  stripeWidth: document.querySelector("#stripeWidth"),
  contrast: document.querySelector("#contrast"),
  duration: document.querySelector("#duration"),
  toggle: document.querySelector("[data-toggle]"),
  fullscreen: document.querySelector("[data-fullscreen]"),
  reset: document.querySelector("[data-reset]"),
  status: document.querySelector("[data-status]"),
  speedOutput: document.querySelector("[data-speed-output]"),
  widthOutput: document.querySelector("[data-width-output]"),
  contrastOutput: document.querySelector("[data-contrast-output]"),
  durationOutput: document.querySelector("[data-duration-output]"),
};

let state = {
  running: false,
  direction: "right",
  offset: 0,
  lastTimestamp: 0,
  startedAt: 0,
  elapsedBeforePause: 0,
  animationId: 0,
};

function getSettings() {
  return {
    speed: Number(controls.speed.value),
    stripeWidth: Number(controls.stripeWidth.value),
    contrast: Number(controls.contrast.value),
    duration: Number(controls.duration.value),
  };
}

function updateOutputs() {
  const settings = getSettings();
  controls.speedOutput.value = `${settings.speed} px/s`;
  controls.widthOutput.value = `${settings.stripeWidth} px`;
  controls.contrastOutput.value = `${settings.contrast}%`;
  controls.durationOutput.value = settings.duration === 0 ? "不限时" : `${settings.duration} s`;
}

function resizeCanvas() {
  const rect = frame.getBoundingClientRect();
  const scale = window.devicePixelRatio || 1;
  canvas.width = Math.max(1, Math.floor(rect.width * scale));
  canvas.height = Math.max(1, Math.floor(rect.height * scale));
  canvas.style.width = `${rect.width}px`;
  canvas.style.height = `${rect.height}px`;
  context.setTransform(scale, 0, 0, scale, 0, 0);
  draw();
}

function stripeColor(index, contrast) {
  const light = 246;
  const dark = Math.round(246 - (contrast / 100) * 236);
  const value = index % 2 === 0 ? dark : light;
  return `rgb(${value} ${value} ${value})`;
}

function draw() {
  const rect = frame.getBoundingClientRect();
  const { stripeWidth, contrast } = getSettings();
  const period = stripeWidth * 2;
  const isVertical = state.direction === "right" || state.direction === "left";
  const length = isVertical ? rect.width : rect.height;
  const crossLength = isVertical ? rect.height : rect.width;
  const normalizedOffset = ((state.offset % period) + period) % period;
  const start = -period + normalizedOffset;

  context.clearRect(0, 0, rect.width, rect.height);

  for (let position = start, index = 0; position < length + period; position += stripeWidth, index += 1) {
    context.fillStyle = stripeColor(index, contrast);
    if (isVertical) {
      context.fillRect(position, 0, stripeWidth + 0.5, crossLength);
    } else {
      context.fillRect(0, position, crossLength, stripeWidth + 0.5);
    }
  }
}

function updateTimer(timestamp) {
  const elapsed = state.running
    ? state.elapsedBeforePause + (timestamp - state.startedAt) / 1000
    : state.elapsedBeforePause;

  const duration = Number(controls.duration.value);
  if (state.running && duration > 0 && elapsed >= duration) {
    pause();
  }
}

function animate(timestamp) {
  if (!state.running) return;

  if (!state.lastTimestamp) state.lastTimestamp = timestamp;
  const deltaSeconds = Math.min(0.05, (timestamp - state.lastTimestamp) / 1000);
  state.lastTimestamp = timestamp;

  const speed = Number(controls.speed.value);
  const sign = state.direction === "right" || state.direction === "down" ? 1 : -1;
  state.offset += speed * deltaSeconds * sign;
  draw();
  updateTimer(timestamp);
  state.animationId = window.requestAnimationFrame(animate);
}

function play() {
  if (state.running) return;
  state.running = true;
  state.lastTimestamp = 0;
  state.startedAt = performance.now();
  controls.toggle.textContent = "暂停";
  controls.status.textContent = "Running";
  controls.status.classList.add("is-running");
  state.animationId = window.requestAnimationFrame(animate);
}

function pause() {
  if (!state.running) return;
  state.elapsedBeforePause += (performance.now() - state.startedAt) / 1000;
  state.running = false;
  window.cancelAnimationFrame(state.animationId);
  controls.toggle.textContent = "开始";
  controls.status.textContent = "Paused";
  controls.status.classList.remove("is-running");
  updateTimer(performance.now());
}

function reset() {
  pause();
  state.offset = 0;
  state.elapsedBeforePause = 0;
  controls.status.textContent = "Ready";
  draw();
}

function setDirection(value) {
  state.direction = value;
  updateOutputs();
  draw();
}

controls.toggle.addEventListener("click", () => {
  if (state.running) {
    pause();
  } else {
    play();
  }
});

controls.fullscreen.addEventListener("click", async () => {
  if (document.fullscreenElement) {
    await document.exitFullscreen();
  } else {
    await frame.requestFullscreen();
  }
});

controls.reset.addEventListener("click", reset);

for (const input of [controls.speed, controls.stripeWidth, controls.contrast, controls.duration]) {
  input.addEventListener("input", () => {
    updateOutputs();
    draw();
  });
}

for (const radio of document.querySelectorAll("input[name='direction']")) {
  radio.addEventListener("change", (event) => setDirection(event.target.value));
}

window.addEventListener("resize", resizeCanvas);
document.addEventListener("fullscreenchange", () => {
  window.setTimeout(resizeCanvas, 120);
});

updateOutputs();
resizeCanvas();
