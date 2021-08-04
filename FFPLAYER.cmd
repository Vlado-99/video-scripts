@rem C:\mediatools\ffmpeg\bin\ffplay.exe -hide_banner -stats -vf "scale=w='min(iw,800):h=-1'" $1
"%~dp0FFMASTER.pl.cmd" --play %*
