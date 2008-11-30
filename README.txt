Copyright (C) 2008 Mauricio Fernandez <mfp@acm.org>
          (C) 2007 Jean-Francois Richard <jean-francois@richard.name>

gibak -- backup tool based on Git
=================================
Since gibak builds upon the infrastructure offered by Git, it shares its main
strengths:
* speed: recovering your data is faster that cp -a...
* full revision history
* space-efficient data store, with file compression and textual/binary deltas
* efficient transport protocol to replicate the backup (faster than rsync)

gibak uses Git's hook system to save and restore the information Git doesn't
track itself such as permissions, empty directories and optionally mtime
fields.

Dependencies
============
gibak needs the following software at run-time:
* git (tested with git version 1.5.4.2, might work with earlier versions)
* rsync >= 2.6.4 (released on 30 March 2005), used to manage nested git
  repositories (submodules)
* common un*x userland: bash, basename, pwd, hostname, cut, grep,
  egrep, date...

It needs the following software to compile:
* ocaml (tested with version 3.10.1 and 3.10.2)
* omake 
* ocaml-fileutils
* Findlib

To install dependencies on Mac:
* sudo port install git-core rsync caml-findlib omake
* There is no port for ocaml-fileutils; you'll have to build it from source at http://le-gall.net/sylvain+violaine/download/ocaml-fileutils-latest.tar.gz

Installation
============

(1) Verify the compilation parameters in OMakefile. The defaults should work
in most cases, but you might need to change a couple variables:
* include paths for the caml headers, required in some OCaml setups
* support for extended attributes. Tested on Linux and OSX.

(2) run

 $ omake

(3) copy the following executables to a directory in your path:

  find-git-files
  find-git-repos
  gibak
  ometastore

Usage
=====
Run gibak without any options to get a help message.

The normal workflow is:

 $ gibak init        # run once to initialize the backup system
 $ vim .gitignore    # edit to make sure you don't import unwanted files
                     # edit .gitignore files in other subdirectories
                     # you can get a list of the files which will be saved
                     # with  find-git-files  or  gibak ls-new-files
 $ gibak commit      # the first commit will be fairly slow, but the following
                     # ones will be very fast

.... later ....

 $ gibak commit

The backup will be placed in $HOME/.git. "Nested Git repositories" will be
rsync'ed to $HOME/.git/git-repositories and they will be registered as
submodules in the main Git repository (run  git help submodule  for more
information on submodules). You might want to use a cronjob to save snapshots
of the repositories in $HOME/.git/git-repositories 

After you gibak init, $HOME becomes a git repository, so you can use normal git
commands. If you use "gibak commit", however, new files will automatically be
added to the repository if they are not ignored (as indicated in your
.gitignore files), so you'll normally prefer it to "git commit".

About the backup store
----------------------
The backup data is placed in $HOME/.git. You can mount an external disk there
if you want your backup to reside in a different physical disk for resiliency
against disk crashes. You can also clone the repository (probably using a bare
repository --- without working tree --- for smaller space usage) and rsync
.git/git-repositories to remote machines for further protection.

Multiple machines
-----------------
You can clone your home directory on another machine, but it's a little 
tricky: git won't let you clone into an existing directory.  Also, git won't
copy the links in .git/hooks, which we use to update the metadata on each
checkout.  Be sure that your UID and GUID are the same on both machines!

So, to clone from your desktop to your laptop, do this on the laptop:

1. Copy over gibak and ometastore to a directory in your path
/Users/bob$ sudo -s
/Users/bob# cd /usr/local/bin
/usr/local/bin# scp desktop:/usr/local/bin/gibak .
/usr/local/bin# scp desktop:/usr/local/bin/ometastore .

1. Do the initial clone

/usr/local/bin# cd ~bob
/Users/bob# cd ..
/Users# mkdir bob-temp
/Users# git clone desktop:.git bob-temp
/Users# ls bob-temp
Documents/
Library/
...etc...
/Users# mv bob-temp/* /Users/bob

This will fail to move any directories that already exist in your 
home directory.  I'm sure there's a nice, safe way around that, so someone
should update these docs with that magic solution.

2. Link the hooks and update your metadata:

/Users# cd bob
/Users/bob# ln -s .git-hooks/* .git/hooks
/Users/bob# .git/hooks/post-checkout
...any errors will be displayed...

3. Recommit
/Users/bob# exit
/Users/bob$ gibak commit

4. Push back to the desktop

[THIS needs some serious documentation.  "git push" is NOT the way to go;
you can't push into a repository with an active working copy!  That will
leave desktop in a state where it incorrectly thinks it's out of date.

I haven't figured this part out yet, but clues are at:

http://hans.fugal.net/blog/2008/11/10/git-push-is-worse-than-worthless

and

http://git.or.cz/gitwiki/GitFaq#head-b96f48bc9c925074be9f95c0fce69bcece5f6e73

...]

5. Periodic synchronization

When you want to sync the laptop, just:

/Users/bob$ git pull
...
/Users/bob$ git that-magic-alternative-to-push-someone-wrote-about-in-step-4

Known Bugs
==========

* .gitignore patterns ending in "/" should match directories, but not files, per "man gitignore".  
  We fail to match them at all!  Workaround: be sure that none of your directory patterns will
  accidentally match a file, and then just remove the trailing slashes.
  
* ometastore gets confused trying to do chown and utime on symlinks.  It spits a harmless error
  out, but this should be cleaned up.


License
=======
The gibak script is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 2 of the License, or (at your option) any
later version.

The ometastore, find-git-files and find-git-repos programs are distributed
under the terms of the GNU Library General Public License version 2.1 (found
in LICENSE). All .ml source files are referred as "the Library" hereunder.

As a special exception to the GNU Lesser General Public License, you may link,
statically or dynamically, a "work that uses the Library" with a publicly
distributed version of the Library to produce an executable file containing
portions of the Library, and distribute that executable file under terms of
your choice, without any of the additional requirements listed in clause 6 of
the GNU Lesser General Public License.  By "a publicly distributed version of
the Library", we mean either the unmodified Library as distributed by the
author, or a modified version of the Library that is distributed under the
conditions defined in clause 2 of the GNU Lesser General Public License.  This
exception does not however invalidate any other reasons why the executable
file might be covered by the GNU Lesser General Public License.

