import { app } from './app.js';

const port = Number.parseInt(process.env.PORT ?? '8787', 10);
const host = '0.0.0.0';

app.listen(port, host, () => {
  console.log(
    `ChefBase recipe import backend listening on http://${host}:${port}`,
  );
});
