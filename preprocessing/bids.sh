# trying to change names to bid formats
files=(*fif)
i=1
for f in $files; do
  mv "$f" "sub-01_ses-01_task-IceSkating_run-$(printf "%02d" $i).fif"
  i=$((i+1))
done

