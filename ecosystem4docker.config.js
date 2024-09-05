module.exports = {
  /**
   * Application configuration section
   * http://pm2.keymetrics.io/docs/usage/application-declaration/
   */
  apps: [
    {
      name: 'gallery-front-web',
      script: 'server.js',
      exec_mode: 'cluster',
      instances: 0,
      env: {
        COMMON_VARIABLE: 'true',
      },
      env_production: {
        APP_ENV: 'production',
      },
      env_staging: {
        APP_ENV: 'staging',
      },
      env_dev: {
        APP_ENV: 'development',
      },
      // disable pm2 logs
      out_file: '/dev/null',
      error_file: '/dev/null',
    },
  ]
};
