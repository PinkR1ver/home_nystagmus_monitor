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

const storySteps = document.querySelectorAll("[data-step]");

if ("IntersectionObserver" in window && storySteps.length > 0) {
  const activeObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          storySteps.forEach((node) => node.classList.remove("is-active"));
          entry.target.classList.add("is-active");
        }
      });
    },
    {
      rootMargin: "-35% 0px -45% 0px",
      threshold: 0.05
    }
  );

  storySteps.forEach((node) => activeObserver.observe(node));
}

const parallaxNodes = document.querySelectorAll("[data-parallax]");

const updateParallax = () => {
  const y = window.scrollY || window.pageYOffset;
  parallaxNodes.forEach((node) => {
    const speed = Number(node.getAttribute("data-parallax")) || 0;
    node.style.transform = `translate3d(0, ${y * (speed / 1000)}px, 0)`;
  });
};

if (parallaxNodes.length > 0) {
  updateParallax();
  window.addEventListener("scroll", updateParallax, { passive: true });
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

if ("IntersectionObserver" in window && serverGuide) {
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
