# trying to change names to bid formats for one subject
files=(*fif)
i=1
for f in $files; do
  mv "$f" "sub-01_ses-01_task-IceSkating_run-$(printf "%02d" $i)_meg.fif"
  i=$((i+1))  # (( )) for arithmetic expansion which can read i without $ vs. () for running command and taking output
done

