# simple-2mic-interferometer

This project contins the software needed for a basic 2-element audio interferometry system. It uses two microphones connected to a small FPGA, which first filters the microphone data and then passes the two sample data streams to a connected computer over a serial connection. On the connected computer, the sample streams are read into a buffer using a simpe Python script and the two are correlated and plotted (using Qt) in close-to-real time. By making sound and varying your relative distance to the two microphones, you can watch the peak of the correlation function shift back and forth, providing a rudimentary way to measure the direction of arrival of the sound. You can also see how the shape of the correlation function changes with different frequency content of the sound signal (speaking, whistling, clapping, hissing, etc).

## Required components:

- An ICEStick FPGA ( https://www.latticesemi.com/icestick )
- 2 digital MEMS microphones ( https://nl.mouser.com/ProductDetail/CUI-Devices/DEVKIT-MEMS-001?qs=sGAEpiMZZMv0NwlthflBi7DsQIGXsWr2Wd5MjRyQhvY%3D )
- enough jumper wires and header pins to connect everything together: minimum of 4 wires per microphone needed if the SET pin is soldered to connect to the VDD pin.

See the photos in the subfolder of this repository for how everything fits together. They are not very good, sorry :( If you have questions, please get in touch and I should be able to provide some more detail.

## Notes for the working version:

There are only 2 files that are important for the working 2-element interferometer:

- The working FPGA code for 2 microphones is >> 2mics-output.bin <<. This FPGA code simply outputs the sample streams from both microphones over the serial connection. This code can be flashed onto the ICEstick using the command: >> iceprog 2mics-output.bin <<. Be sure to have the open-source toolchain installed: it includes yosys, icestorm, arachne-pnr and nextpnr. See for instance https://eecs.blog/lattice-ice40-fpga-icestorm-tutorial/ , although there are many tutorials online. Also be sure to check the USB driver setup bit directly below in these notes.

- Correlation for the working version is performed by the code running on the laptop, in the script >> simpleworkingqtplot.py <<. This can simply be run from the command line using >> python3 simpleworkingqtplot.py <<, or from within an ipython session.

- All other files are experimental versions, support files, intermediate products or tests, and are not critical to running the system. They are included to provide some extra inroads into experimentation for the enthusiastic user.

## Things to watch out for when dealing with the 2-microphone ICEstick setup on OSX:

- Reading the USB serial input as a virtual COM port only works when using the FTDI USB serial drivers.
  To use these, first unload the Apple FTDI driver:

  sudo kextunload /System/Library/Extensions/AppleUSBFTDI.kext/

  and then load the FTDI driver:

  sudo kextload -b com.FTDI.driver.FTDIUSBSerialDriver

  The ICEstick can now send data over its serial connection using programs like Coolterm or screen.

- Programming the ICEstick requires the other set of drivers to be active:

  sudo kextunload /System/Library/Extensions/FTDIUSBSerialDriver.kext/

  sudo kextload -b com.apple.driver.AppleUSBFTDI

  then running the command 'iceprog XXX.bin'.

  Note that sometimes, the system forgets either and then has no FTDI drivers active at all.
  Just reload the relevant driver to make it wake up again.

## Notes written during development

Note that these were written as the work progressed, so that they are typically not valid anymore for the current version!

- arachne-pnr sometimes has problems routing the wires. Changing the bit width of some variables seemed to help in resolving this. Odd how a bit width of 16 instead of 8 for the CIC output signals resolved this issue.

- In the current setup, I have a baud rate of 800000 but I am trying to send too much data over this connection. Halving the data rate by only sending 1 byte per sample gives pretty bad dynamic range.

- I will likely have to change the effective sample rate of the microphones from 46875 Hz to something like half that. The reason for this is that when reading out 2 microphone data streams at the rate of 46875 samples per second and 8 bit depth, I need a baud rate of 2 x 10 x 46875 = 937500 which is dangerously close to the absolute maximum of 1 Mbit/s.

- I have changed the decimation factor to 512 in the CIC filter code. This gives us a much lower sample rate, something close to 6000 Hz or so. I should now be able to transmit 16-bit samples from 2 mics within a reasonable bandwidth (20 x 2 x 6000 = ~240000 bits/sec).

- For some reason, the bit range I select to transmit determines whether the design can be placed properly (?). The width of the range stays the same, just the selected interval (e.g., 30:15 or 15:0) has an influence. Some choices need a lot more LCs than others, and I don't understand why.

- I have reduced the order of the CIC filter from 5 to 4 by removing one stage from the integrator and also one from the comb. This now seems to compile, and with one mic connected the signal looks like it makes sense (although it seems to glitch sometimes). Now we will have to see what happens with 2 mics!

- I got issues when synthesizing the design for 2 mics, resource usage was too high. I have reduced the CIC filters by another order (now it is 3), and this works well. I get 16-bit samples at a sampling rate of 3 MHz / 256 = 11.7 kHz for 2 mics. For some reason, non-power-of-2 decimation factors give me problems.

- After fiddling with the serial interface on the laptop side some more, I now have a robust way of dealing with the data stream. One in every 512 samples for mic 1 is assigned the value FF FF, which I can look for in the data stream. This provides me with a reference position to pick out all the correct bytes per mic, and per LSB/MSB. Using Pyqtgraph, I can plot the correlation function in real time.



