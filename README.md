ensembl-hive-slurm
==================


SLURM Meadow for Ensembl-Hive
-------

[eHive](https://travis-ci.org/Ensembl/ensembl-hive) is a system for running computation pipelines on distributed computing resources - clusters, farms or grids.

This repository is the implementation of eHive's _Meadow_ interface for the SLURM job scheduler.


Version numbering and compatibility
-----------------------------------

This repository is versioned the same way as eHive itself
* `tag/v3.0` works with eHive v80, eHive Meadow v3.0 and SLURM 17.11.11 
* `tag/v5.3` works with eHive v90, eHive Meadow v5.3 and SLURM 17.11.11 

* `master` is the stable branch branch
* `develop` is - guess what - the development branch branch.

Contributors
------------

This module was initially released by my friend [Petr Votava](https://github.com/votavap) (Genentech) based on the LSF.pm module. 
