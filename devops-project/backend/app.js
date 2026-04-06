const express = require('express');
const app = express();

const PORT = 3000;

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

app.get('/api', (req, res) => {
  res.json({ message: 'Backend API running on EKS — Push #3' });
});

app.get('/', (req, res) => {
  res.json({ message: 'Backend API running on EKS' });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});