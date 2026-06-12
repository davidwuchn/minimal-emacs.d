// CreatorOS popup — connects user actions to engine
document.getElementById('openDashboard').addEventListener('click', () => {
  chrome.tabs.create({ url: 'http://localhost:8080/dashboard' });
});
document.getElementById('refreshData').addEventListener('click', () => {
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    chrome.tabs.sendMessage(tabs[0].id, { action: 'refresh' });
  });
});
