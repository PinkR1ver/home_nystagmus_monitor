const revealNodes = document.querySelectorAll(".reveal");

if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    },
    {
      rootMargin: "0px 0px -12% 0px",
      threshold: 0.16
    }
  );

  revealNodes.forEach((node) => observer.observe(node));
} else {
  revealNodes.forEach((node) => node.classList.add("is-visible"));
}

const compareSlider = document.querySelector("[data-compare-slider]");
const afterLayer = document.querySelector("[data-after-layer]");
const divider = document.querySelector("[data-divider]");

if (compareSlider && afterLayer && divider) {
  const updateCompare = (value) => {
    const clamped = Math.max(0, Math.min(100, Number(value)));
    afterLayer.style.clipPath = `inset(0 0 0 ${clamped}%)`;
    divider.style.left = `${clamped}%`;
  };

  updateCompare(compareSlider.value);
  compareSlider.addEventListener("input", (event) => {
    updateCompare(event.target.value);
  });
}

const serverGuide = document.querySelector("#server-guide");
const guideCards = document.querySelectorAll("[data-guide-card]");

if ("IntersectionObserver" in window && serverGuide && guideCards.length > 0) {
  const guideObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          serverGuide.classList.add("is-active");
        } else {
          serverGuide.classList.remove("is-active");
        }
      });
    },
    {
      rootMargin: "-18% 0px -45% 0px",
      threshold: 0.05
    }
  );

  guideObserver.observe(serverGuide);
}

const updateGuideDepth = () => {
  if (!serverGuide) return;
  const rect = serverGuide.getBoundingClientRect();
  const vh = window.innerHeight || 1;
  const progress = 1 - Math.max(0, Math.min(1, (rect.top + rect.height - vh * 0.15) / (rect.height + vh * 0.4)));
  serverGuide.style.setProperty("--guide-depth", progress.toFixed(3));

  guideCards.forEach((card, index) => {
    const cardRect = card.getBoundingClientRect();
    const centerDistance = Math.abs(cardRect.top + cardRect.height / 2 - vh * 0.45);
    const emphasis = Math.max(0, 1 - centerDistance / (vh * 0.75));
    card.style.opacity = String(0.58 + emphasis * 0.42);
    card.style.setProperty("--card-shift", `${(1 - emphasis) * 12}px`);
    card.style.setProperty("--card-scale", `${0.985 + emphasis * 0.02}`);
    card.style.zIndex = String(10 + Math.round(emphasis * 10) + index);
  });
};

if (serverGuide && guideCards.length > 0) {
  updateGuideDepth();
  window.addEventListener("scroll", updateGuideDepth, { passive: true });
  window.addEventListener("resize", updateGuideDepth);
}
