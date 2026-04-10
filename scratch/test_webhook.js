const http = require('http');

const data = JSON.stringify({
  sender: '+1234567890',
  message: 'Verification Test: Your SMS Forwarder is working correctly!',
  date: new Date().toISOString()
});

const options = {
  hostname: 'localhost',
  port: 3000,
  path: '/sms',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': data.length
  }
};

const req = http.request(options, (res) => {
  console.log(`Status Code: ${res.statusCode}`);
  res.on('data', (d) => {
    process.stdout.write(d);
  });
});

req.on('error', (error) => {
  console.error(error);
});

req.write(data);
req.end();
