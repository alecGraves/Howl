# Howl 🐺🎶🎵🎶🎼🎹

Howl is a 🐺 Wolfram Language / ➕ Mathematica library for training computers to generate music.

I have really wanted to do this project for a while now, and I am very happy to have been able to work on it.

If anyone else is interested in adding new functionality or their own models, please feel free to contribute through issues / github.

## License

This software is released under the Unlicense, so basically do whatever you want with it.

## Usage

The core functionality is *right now* in a wolfram language package called HowlMidiTools

To load the functions exposed by the library, simply run:

```mathematica
SetDirectory["Howl"]; (* Wherever the git repo is *)
<< "Howl/HowlMidiTools.wl"
```

To generate a dataset for training from a collection of .mid ("MIDI") files, you can simply run:

```mathematica
datasetPath = "/path/to/my/.mid/files";
dataset = Map[HowlMidiImport, HowlFindMidis[datasetPath]];
datasetEncoded =(Key["EncodedNotesV1"]/@dataset) /.
    _Missing -> Nothing
```

This stores each of your midi songs as a list of `{{timeFromPrevNote, noteDuration, noteVelocity, noteIntegerPitch}, ...}`.

Now, you can use this note data to train your neural network to generate music. See [this helpful guide][1] for information about modeling sequential data with neural nets.

You can also use the Scripts/trainRnn.wls script as a starting point for your training. 

[1]: https://www.wolfram.com/language/12/neural-network-framework/train-a-net-to-model-english.html?product=mathematica
