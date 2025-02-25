const Fastify = require('fastify');

async function build() {
  const fastify = Fastify({
    logger: true,
  });

  // Register PostgreSQL via PgBouncer
  fastify.register(require('@fastify/postgres'), {
    connectionString: 'postgres://dhana:htxpp-client@localhost:6432/htxppdb',
    // Additional recommended settings
    pool: {
      min: 2,
      max: 10,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    },
  });

  // Test endpoint
  fastify.get('/test', async (request, reply) => {
    try {
      const result = await fastify.pg.query('SELECT NOW() as current_time');
      return {
        status: 'success',
        time: result.rows[0].current_time,
      };
    } catch (err) {
      fastify.log.error(err);
      return reply.code(500).send({ error: 'Database connection failed' });
    }
  });

  // Health check endpoint
  fastify.get('/health', async (request, reply) => {
    try {
      await fastify.pg.query('SELECT 1');
      return { status: 'healthy' };
    } catch (err) {
      fastify.log.error(err);
      return reply.code(503).send({ status: 'unhealthy' });
    }
  });

  return fastify;
}

// Start the server
async function start() {
  const fastify = await build();
  try {
    await fastify.listen({ port: 3000, host: '0.0.0.0' });
    console.log('Server running at http://localhost:3000');
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
}

start();
