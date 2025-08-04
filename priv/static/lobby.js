
let currentGameId = null;

// Load games and current player game on page load
document.addEventListener('DOMContentLoaded', () => {
  loadGames();
  loadCurrentPlayerGame();
});

// Create game form handler
document.getElementById('create-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const gameName = document.getElementById('game-name').value;

  try {
    const response = await fetch(`/create-game/${encodeURIComponent(gameName)}`, {
      method: 'GET'
    });

    if (response.ok) {
      const game = await response.json();
      showStatus(`Game '${game.name}' created successfully!`, 'success');
      document.getElementById('game-name').value = '';
      loadGames();
      loadCurrentPlayerGame();
    } else {
      showStatus('Failed to create game', 'error');
    }
  } catch (error) {
    showStatus('Error creating game', 'error');
  }
});

// Refresh games button
document.getElementById('refresh-games').addEventListener('click', () => {
  loadGames();
  loadCurrentPlayerGame();
});

// Leave game button
document.getElementById('leave-game').addEventListener('click', async () => {
  try {
    const response = await fetch('/leave-game', { method: 'GET' });
    if (response.ok) {
      showStatus('Left game successfully', 'success');
      loadGames();
      loadCurrentPlayerGame();
    } else {
      showStatus('Failed to leave game', 'error');
    }
  } catch (error) {
    showStatus('Error leaving game', 'error');
  }
});

// Load available games
async function loadGames() {
  try {
    const response = await fetch('/list-games');
    const games = await response.json();

    const gamesList = document.getElementById('games-list');

    if (games.length === 0) {
      gamesList.innerHTML = '<p style=\"color: #718096\">No games available. Create one!</p>';
      return;
    }

    gamesList.innerHTML = games.map(game => `
      <div class=\"game-item\">
        <div class=\"game-info\">
          <h3>${game.name}</h3>
          <p>Players: ${game.player_count}/${game.max_players} • Status: ${game.status}</p>
        </div>
        <button class=\"btn\" onclick=\"joinGame('${game.id}')\">Join</button>
      </div>
    `).join('');
  } catch (error) {
    document.getElementById('games-list').innerHTML = '<p style=\"color: #e53e3e\">Error loading games</p>';
  }
}

// Load current player game
async function loadCurrentPlayerGame() {
  try {
    const response = await fetch('/get-player-game');
    const game = await response.json();

    const currentGameInfo = document.getElementById('current-game-info');

    if (game) {
      currentGameId = game.id;
      currentGameInfo.innerHTML = `
        <div class=\"game-item current-game\">
          <div class=\"game-info\">
            <h3>🎯 Current Game: ${game.name}</h3>
            <p>Players: ${game.player_count}/${game.max_players} • Status: ${game.status}</p>
          </div>
          <button class=\"btn\" onclick=\"enterGame('${game.id}')\">Enter Game</button>
        </div>
      `;
    } else {
      currentGameId = null;
      currentGameInfo.innerHTML = '';
    }
  } catch (error) {
    console.error('Error loading current player game:', error);
  }
}

// Join a game
async function joinGame(gameId) {
  try {
    const response = await fetch(`/join-game/${gameId}`, { method: 'GET' });

    if (response.ok) {
      const game = await response.json();
      showStatus(`Joined game '${game.name}'!`, 'success');
      loadGames();
      loadCurrentPlayerGame();
    } else {
      showStatus('Failed to join game', 'error');
    }
  } catch (error) {
    showStatus('Error joining game', 'error');
  }
}

// Enter a game (navigate to game page)
function enterGame(gameId) {
  window.location.href = `/game/${gameId}`;
}

// Show status message
function showStatus(message, type) {
  const status = document.getElementById('status');
  status.textContent = message;
  status.className = `status ${type}`;
  status.style.display = 'block';
  
  setTimeout(() => {
    status.style.display = 'none';
  }, 5000);
}

// Auto-refresh games every 5 seconds
setInterval(() => {
  loadGames();
  loadCurrentPlayerGame();
}, 5000);
