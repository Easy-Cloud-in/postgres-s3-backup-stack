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

  // Create users table if it doesn't exist
  fastify.addHook('onReady', async () => {
    try {
      await fastify.pg.query(`
        CREATE TABLE IF NOT EXISTS users (
          id SERIAL PRIMARY KEY,
          name VARCHAR(100) NOT NULL,
          email VARCHAR(100) UNIQUE NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
      fastify.log.info('Database schema initialized');
    } catch (err) {
      fastify.log.error('Failed to initialize database schema:', err);
    }
  });

  // Add user endpoint
  fastify.post(
    '/users',
    {
      schema: {
        body: {
          type: 'object',
          required: ['name', 'email'],
          properties: {
            name: { type: 'string' },
            email: { type: 'string', format: 'email' },
          },
        },
        response: {
          201: {
            type: 'object',
            properties: {
              id: { type: 'integer' },
              name: { type: 'string' },
              email: { type: 'string' },
              created_at: { type: 'string', format: 'date-time' },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const { name, email } = request.body;

      try {
        const result = await fastify.pg.query(
          'INSERT INTO users (name, email) VALUES ($1, $2) RETURNING *',
          [name, email]
        );

        const newUser = result.rows[0];
        reply.code(201);
        return newUser;
      } catch (err) {
        fastify.log.error(err);

        // Handle duplicate email error
        if (err.code === '23505') {
          return reply.code(409).send({
            error: 'Conflict',
            message: 'A user with this email already exists',
          });
        }

        return reply.code(500).send({
          error: 'Internal Server Error',
          message: 'Failed to create user',
        });
      }
    }
  );

  // Get all users endpoint
  fastify.get('/users', async (request, reply) => {
    try {
      const result = await fastify.pg.query('SELECT * FROM users ORDER BY id');
      return { users: result.rows };
    } catch (err) {
      fastify.log.error(err);
      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Failed to retrieve users',
      });
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
