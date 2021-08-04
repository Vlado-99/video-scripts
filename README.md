# video-scripts
Set of scripts to convert videorecordings using ffmpeg tools.

# prerequisities

  * Windows operating system
  * Installed [ffmpeg tools](https://ffmpeg.org/download.html) into `C:\mediatools\ffmpeg` directory
  * Installed [Strawberry Perl](https://strawberryperl.com/) into usual location `C:\Strawberry`

# installation

Copy this files and dirs into `C:\mediatools`.

# usage

**FFMASTER**

Use it to prepare new conversion job and push of job into queue.
Use drag-and-drop of videofile to script file.

**FFMASTER--run-as-daemon**

This is a daemon, which does the real work - processing of job files. Stops automatically when there is no more jobs in queue.

**FFPLAYER**

Use it to play video file. From player you can get usefull data, when you need trim videorecording.
Use drag-and-drop of videofile to script file.

**FFPROBE**

Use it to show properties of videofile content.
Use drag-and-drop.

**FFJOIN**

Use it to join multi-file video recording.
You have to open command line (`cmd`) and call `FFJOIN` with file names you want to join together.
