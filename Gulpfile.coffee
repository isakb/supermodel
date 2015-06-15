gulp       = require 'gulp'
gp         = do require 'gulp-load-plugins'
paths =
  app:
    js: [
      'src/*.coffee'
    ]

gulp.task 'js', ->
  gulp.src(paths.app.js)
    .pipe gp.coffee(bare: true)
    .pipe gp.browserify()
    .pipe gulp.dest('dist/')

gulp.task 'watch', ->
  gulp.watch paths.app.js, ['js']
  return

gulp.task 'build', [
  'js'
]

gulp.task 'default', [
  'build'
  'watch'
]
