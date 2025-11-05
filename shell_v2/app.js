/**
 * Stiletto Proto - Web Shell v2
 * Application Management & Game Launcher
 */

// ============================================
// Configuration
// ============================================

const CONFIG = {
	// View IDs
	views: ['home', 'play', 'settings', 'stats', 'about'],
	
	// Element IDs
	appContainer: 'app-container',
	gameContainer: 'game-container',
	canvas: 'canvas',
	gameLoading: 'game-loading',
	gameOverlay: 'game-overlay',
	errorDisplay: 'error-display',
	progressBar: 'progress-bar',
	progressText: 'progress-text',
	statusText: 'status-text',
	errorMessage: 'error-message',
	
	// Settings
	defaultSettings: {
		video: {
			resolution: 'auto',
			quality: 'high',
			vsync: true
		},
		audio: {
			master: 80,
			music: 60,
			sfx: 80
		},
		controls: {
			sensitivity: 5,
			invertY: false
		},
		gameplay: {
			showFPS: true,
			crosshair: true
		}
	}
};

// ============================================
// Application State
// ============================================

const AppState = {
	currentView: 'home',
	isGameRunning: false,
	settings: { ...CONFIG.defaultSettings },
	
	init() {
		this.loadSettings();
	},
	
	loadSettings() {
		const saved = localStorage.getItem('stiletto_settings');
		if (saved) {
			try {
				this.settings = { ...CONFIG.defaultSettings, ...JSON.parse(saved) };
			} catch (e) {
				console.warn('Failed to load settings:', e);
			}
		}
	},
	
	saveSettings() {
		localStorage.setItem('stiletto_settings', JSON.stringify(this.settings));
		console.log('Settings saved');
	},
	
	resetSettings() {
		this.settings = { ...CONFIG.defaultSettings };
		this.saveSettings();
		ViewManager.refreshSettingsUI();
		console.log('Settings reset to defaults');
	}
};

// ============================================
// View Management
// ============================================

const ViewManager = {
	currentView: null,
	
	init() {
		// Set up navigation links
		document.querySelectorAll('[data-view]').forEach(link => {
			link.addEventListener('click', (e) => {
				e.preventDefault();
				const viewName = link.getAttribute('data-view');
				this.switchView(viewName);
			});
		});
		
		// Initialize with home view
		this.switchView('home');
	},
	
	switchView(viewName) {
		// Deactivate current view
		if (this.currentView) {
			const currentViewElement = document.getElementById(`view-${this.currentView}`);
			if (currentViewElement) {
				currentViewElement.classList.remove('active');
			}
		}
		
		// Deactivate current nav link
		document.querySelectorAll('[data-view]').forEach(link => {
			link.classList.remove('active');
		});
		
		// Activate new view
		const newViewElement = document.getElementById(`view-${viewName}`);
		if (newViewElement) {
			newViewElement.classList.add('active');
			this.currentView = viewName;
			AppState.currentView = viewName;
		}
		
		// Activate new nav link
		const activeLink = document.querySelector(`[data-view="${viewName}"]`);
		if (activeLink) {
			activeLink.classList.add('active');
		}
		
		console.log(`Switched to view: ${viewName}`);
	},
	
	refreshSettingsUI() {
		// Refresh settings UI with current values
		// This will be expanded when settings are wired up
		console.log('Settings UI refreshed');
	}
};

// ============================================
// Game Management
// ============================================

const GameManager = {
	gameInstance: null,
	
	init() {
		console.log('Game Manager initialized');
	},
	
	startGame() {
		console.log('Starting game...');
		
		// Hide app container
		const appContainer = document.getElementById(CONFIG.appContainer);
		appContainer.classList.add('d-none');
		
		// Show game container
		const gameContainer = document.getElementById(CONFIG.gameContainer);
		gameContainer.classList.remove('d-none');
		
		// Show game overlay
		const gameOverlay = document.getElementById(CONFIG.gameOverlay);
		gameOverlay.classList.remove('d-none');
		
		AppState.isGameRunning = true;
		
		// Initialize game engine here
		this.initializeGameEngine();
	},
	
	exitGame() {
		console.log('Exiting game...');
		
		// Stop game instance if running
		if (this.gameInstance) {
			// Cleanup game instance
			this.gameInstance = null;
		}
		
		// Hide game container
		const gameContainer = document.getElementById(CONFIG.gameContainer);
		gameContainer.classList.add('d-none');
		
		// Show app container
		const appContainer = document.getElementById(CONFIG.appContainer);
		appContainer.classList.remove('d-none');
		
		AppState.isGameRunning = false;
		
		// Return to home view
		ViewManager.switchView('home');
	},
	
	initializeGameEngine() {
		// Placeholder for Godot engine initialization
		// This will be replaced with actual Godot web export code
		
		const gameLoading = document.getElementById(CONFIG.gameLoading);
		const progressBar = document.getElementById(CONFIG.progressBar);
		const progressText = document.getElementById(CONFIG.progressText);
		const statusText = document.getElementById(CONFIG.statusText);
		
		// Simulate loading
		let progress = 0;
		const interval = setInterval(() => {
			progress += Math.random() * 15;
			if (progress >= 100) {
				progress = 100;
				clearInterval(interval);
				
				// Update UI
				progressBar.style.width = '100%';
				progressBar.setAttribute('aria-valuenow', 100);
				progressText.textContent = '100%';
				statusText.textContent = 'Ready!';
				
				// Hide loading after delay
				setTimeout(() => {
					gameLoading.classList.add('fade-out');
					setTimeout(() => {
						gameLoading.style.display = 'none';
					}, 300);
				}, 500);
			} else {
				progressBar.style.width = `${progress}%`;
				progressBar.setAttribute('aria-valuenow', progress);
				progressText.textContent = `${Math.round(progress)}%`;
				statusText.textContent = 'Loading assets...';
			}
		}, 200);
	},
	
	showError(message) {
		const errorDisplay = document.getElementById(CONFIG.errorDisplay);
		const errorMessage = document.getElementById(CONFIG.errorMessage);
		
		errorMessage.textContent = message;
		errorDisplay.classList.remove('d-none');
		errorDisplay.classList.add('d-flex');
		
		const gameLoading = document.getElementById(CONFIG.gameLoading);
		gameLoading.style.display = 'none';
	}
};

// ============================================
// UI Event Handlers
// ============================================

const UIHandlers = {
	init() {
		// Home view buttons
		document.getElementById('btn-quick-play')?.addEventListener('click', () => {
			GameManager.startGame();
		});
		
		document.getElementById('btn-view-settings')?.addEventListener('click', () => {
			ViewManager.switchView('settings');
		});
		
		// Play view buttons
		document.getElementById('btn-play-singleplayer')?.addEventListener('click', () => {
			GameManager.startGame();
		});
		
		// Settings buttons
		document.getElementById('btn-save-settings')?.addEventListener('click', () => {
			AppState.saveSettings();
			this.showNotification('Settings saved successfully!');
		});
		
		document.getElementById('btn-reset-settings')?.addEventListener('click', () => {
			if (confirm('Reset all settings to defaults?')) {
				AppState.resetSettings();
				this.showNotification('Settings reset to defaults');
			}
		});
		
		// Game controls
		document.getElementById('btn-exit-game')?.addEventListener('click', () => {
			if (confirm('Exit to main menu?')) {
				GameManager.exitGame();
			}
		});
		
		document.getElementById('btn-error-back')?.addEventListener('click', () => {
			GameManager.exitGame();
		});
	},
	
	showNotification(message) {
		// Simple console notification for now
		// Could be expanded to a Bootstrap toast
		console.log('Notification:', message);
		alert(message);
	}
};

// ============================================
// Application Initialization
// ============================================

class Application {
	constructor() {
		this.initialized = false;
	}
	
	init() {
		console.log('=================================');
		console.log('Stiletto Proto - Web Shell v2');
		console.log('=================================');
		
		// Initialize subsystems
		AppState.init();
		ViewManager.init();
		GameManager.init();
		UIHandlers.init();
		
		this.initialized = true;
		console.log('Application initialized');
		
		// Check system capabilities
		this.checkSystemCapabilities();
	}
	
	checkSystemCapabilities() {
		const canvas = document.getElementById(CONFIG.canvas);
		const gl = canvas?.getContext('webgl2') || canvas?.getContext('webgl');
		
		if (gl) {
			console.log('✓ WebGL supported');
		} else {
			console.warn('✗ WebGL not supported');
		}
		
		// Add more capability checks as needed
	}
}

// ============================================
// Initialize Application on DOM Ready
// ============================================

let app = null;

document.addEventListener('DOMContentLoaded', () => {
	app = new Application();
	app.init();
});

// ============================================
// Global Error Handling
// ============================================

window.addEventListener('error', (event) => {
	console.error('Error:', event.error);
	if (AppState.isGameRunning) {
		GameManager.showError(event.error?.message || 'An unexpected error occurred.');
	}
});

window.addEventListener('unhandledrejection', (event) => {
	console.error('Unhandled Promise Rejection:', event.reason);
	if (AppState.isGameRunning) {
		GameManager.showError(event.reason?.message || 'An unexpected error occurred.');
	}
});

// ============================================
// Keyboard Shortcuts
// ============================================

document.addEventListener('keydown', (e) => {
	// Escape key to exit game
	if (e.key === 'Escape' && AppState.isGameRunning) {
		if (confirm('Exit to main menu?')) {
			GameManager.exitGame();
		}
	}
});

