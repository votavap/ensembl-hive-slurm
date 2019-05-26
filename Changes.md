## Changes between releases/tags

### v5.3.3

  - Edited SLURM->name() to time out after 300 sec. We saw issues when 
    the Slurm ctl was unresponsive, and all our (running) jobs got marked
    as FAILED, and reset to READY.
  
### v5.3.2 

  - Updated SLURM.pm to capture Out of Memmory events and record them into 
    worker_resource_usage table ( after you ran load_resource_usage.pl ) 

### v5.3.1 

  - Initial version, compatible with Meadow v5.0

