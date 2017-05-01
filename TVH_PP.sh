#!/bin/sh
#set -x #echo on

# TV Converter
# Processes recorded TV program, strips out adverts via Comskip and compresses
function pause(){
   read -p "$*"
}

#Variables and paths

filename=`basename "$1"`
BaseFileName=${1%.*}
EDLFILE=$BaseFileName.edl
FFPROBE=/opt/Qffmpeg/bin/ffprobe
FFMPEG=/opt/Qffmpeg/bin/ffmpeg
COMSKIPPATH="/share/Recording/Tools/comskip"
COMSKIPINI="/share/Recording/Tools/comskip.ini"

#Run COMSKIP first
if [ ! -f "$EDLFILE" ]; then
	$COMSKIPPATH --ini=$COMSKIPINI "$1" 
fi

# If edl file now exists we have something to work with e.g. there are some adverts

if [ -f "$EDLFILE" ]; then

#Now read EDL file into array and count rows
echo "EDL File Exists"
edlrow=1
start[edlrow]=0

while read line; do
end[edlrow]="$( cut -f 1 <<<"$line" )"
start[edlrow+1]="$( cut -f 2 <<<"$line")"
edlrow=$((edlrow+1))
done < "$EDLFILE"

#Set end point to end of file
end[edlrow]=$($FFPROBE -i "$1" -show_entries format=duration -v quiet -of csv="p=0")

# First section starts at first time and goes to second cut point, second section starts at end of cut point 1 etc.

a=1
while [ $a -le $edlrow ]
do
  ffstart=$(echo ${start[$a]}|TZ=UTC awk '{print strftime("%H:%M:%S",$1,-3600)}')
  ffend=$(echo ${end[$a]}|TZ=UTC awk '{print strftime("%H:%M:%S",$1,-3600)}')
  length=$(echo ${end[$a]} ${start[$a]}} | awk '{ printf "%f", $1 - $2 }')
  fflength=$(echo $length|TZ=UTC awk '{print strftime("%H:%M:%S", $1,-3600)}')
  $FFMPEG -ss $ffstart -i "$1" -t $fflength -async 1 -vcodec copy -acodec copy -y "$BaseFileName""_Temp_"$a.ts
  ffparts=$ffparts$BaseFileName"_Temp_"$a.ts"|"
a=$((a+1))
#Finish Looping
done

#Determine if to convert of copy the video

videoformat=$($FFPROBE -i "$1" -show_entries format=bitrate -v quiet -of csv="p=0")

convertvideoformat="-c:v libx264 -profile:v high -preset fast -x264-params crf=24"

if (( videoformat < 3000000 )); then
    convertvideoformat="-vcodec copy "
fi

#Now combine it all again if needed and output to mp4

`$FFMPEG -fflags +genpts -i "concat:$ffparts" $convertvideoformat -acodec ac3 -ac 6 -y -sn -threads 0 "$BaseFileName""_output.mp4"`

# No EDL File so just convert the file
else

`$FFMPEG -fflags +genpts -i "$1" $convertvideoformat -acodec ac3 -ac 6 -y -sn -threads 0 "$BaseFileName""_output.mp4"`

fi


#Finally Clean Up files 

rm -f "$EDLFILE"
rm -f "$BaseFileName""_Temp_"*".ts"

#cp -f "$1" /share/Recording/TV_Converted

#Now Tell TV Headend with trick renaming so TVH finds it

mv "$1" "$BaseFileName"".mp4"

cp -f "$BaseFileName""_output.mp4" "$BaseFileName"".mp4"
rm -f "$BaseFileName""_output.mp4"


#curl -G -v "http://localhost:9981/api/dvr/entry/filemoved?" --data-urlencode "src=$1" --data-urlencode "dst=$BaseFileName.mp4" 

