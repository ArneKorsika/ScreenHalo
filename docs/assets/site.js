function setupGallery() {
  const links = [...document.querySelectorAll('a.zoom')];
  const dialog = document.getElementById('lightbox');

  if (!links.length || !dialog || typeof dialog.showModal !== 'function') {
    return;
  }

  const image = document.getElementById('lb-img');
  const caption = document.getElementById('lb-cap');
  const counter = document.getElementById('lb-count');
  const closeButton = document.getElementById('lb-close');
  const previousButton = document.getElementById('lb-prev');
  const nextButton = document.getElementById('lb-next');
  let currentIndex = 0;
  let previousFocus = null;
  let touchStartX = null;

  function showImage(index) {
    currentIndex = (index + links.length) % links.length;
    const link = links[currentIndex];
    const thumbnail = link.querySelector('img');
    const figureCaption = link.closest('figure')?.querySelector('figcaption');

    image.src = link.getAttribute('href');
    image.alt = thumbnail?.alt ?? '';
    caption.textContent = figureCaption?.textContent ?? '';
    counter.textContent = `${currentIndex + 1} / ${links.length}`;
  }

  links.forEach((link, index) => {
    link.addEventListener('click', (event) => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
        return;
      }

      event.preventDefault();
      previousFocus = link;
      showImage(index);
      dialog.showModal();
      closeButton.focus();
    });
  });

  closeButton.addEventListener('click', () => dialog.close());
  previousButton.addEventListener('click', () => showImage(currentIndex - 1));
  nextButton.addEventListener('click', () => showImage(currentIndex + 1));

  dialog.addEventListener('click', (event) => {
    if (event.target === dialog || event.target.id === 'lb-stage') {
      dialog.close();
    }
  });

  dialog.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowLeft') {
      event.preventDefault();
      showImage(currentIndex - 1);
    } else if (event.key === 'ArrowRight') {
      event.preventDefault();
      showImage(currentIndex + 1);
    }
  });

  dialog.addEventListener('close', () => previousFocus?.focus());

  dialog.addEventListener('touchstart', (event) => {
    touchStartX = event.touches.length === 1 ? event.touches[0].clientX : null;
  }, { passive: true });

  dialog.addEventListener('touchend', (event) => {
    if (touchStartX === null || !event.changedTouches.length) {
      return;
    }

    const distance = event.changedTouches[0].clientX - touchStartX;
    touchStartX = null;

    if (Math.abs(distance) > 50) {
      showImage(currentIndex + (distance < 0 ? 1 : -1));
    }
  });

  dialog.addEventListener('touchcancel', () => {
    touchStartX = null;
  });
}

function setupNavigation() {
  const button = document.getElementById('menu-btn');
  const navigation = document.getElementById('site-nav');

  if (!button || !navigation) {
    return;
  }

  function setMenuOpen(open) {
    navigation.classList.toggle('open', open);
    button.setAttribute('aria-expanded', String(open));
    button.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
  }

  button.addEventListener('click', () => {
    setMenuOpen(!navigation.classList.contains('open'));
  });

  navigation.addEventListener('click', (event) => {
    if (event.target.closest('a')) {
      setMenuOpen(false);
    }
  });

  document.addEventListener('click', (event) => {
    if (!navigation.contains(event.target) && !button.contains(event.target)) {
      setMenuOpen(false);
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && navigation.classList.contains('open')) {
      setMenuOpen(false);
      button.focus();
    }
  });

  window.matchMedia('(min-width: 901px)').addEventListener('change', (event) => {
    if (event.matches) {
      setMenuOpen(false);
    }
  });
}

setupGallery();
setupNavigation();
