## [Training an RNN to Play the Piano 🎹 (link)](https://community.wolfram.com/groups/-/m/t/2328597)
### Sequence Modeling of Musical Note Data
This is a fun personal project I have wanted to do for about a year. I hope you can find this entertaining and informative if you are curious about how to train RNNs (LSTMs and GRUs) on custom, multi-input/output sequential data using the Wolfram Language.

## Generated Music 🎶

Here are some songs the models from this project have generated (after feeding a single random note as a seed):

* [Forgotten Memory 0.1 - 512 node GRU (mp3)](https://graves.tech/assets/piano/Forgotten_Memory_0-1_small.mp3)
  / [(High-Fi FLAC)](https://graves.tech/assets/piano/Forgotten_Memory_0-1.flac)

* [Hopeful 0.1 - 416 node LSTM (mp3)](https://graves.tech/assets/piano/Hopeful_0-1_small.mp3)
  / [(High-Fi FLAC)](https://graves.tech/assets/piano/Hopeful_0-1.flac)

* [Behind the Gate 0.1 - 192 node LSTM (mp3)](https://graves.tech/assets/piano/Behind_The_Gate_0-1_small.mp3)
  / [(High-Fi FLAC)](https://graves.tech/assets/piano/Behind_The_Gate_0-1.flac)

* [Gradient Explosion 0.1 - 192 node LSTM (mp3)](https://graves.tech/assets/piano/Gradient_Explosion_0-1_small.mp3)
  / [(High-Fi FLAC)](https://graves.tech/assets/piano/Gradient_Explosion_0-1.flac)


Pretty musical, right?!?!

And I here is the [192-node LSTM model][model] if you want to generate your own music! (see below for "Output Prediction" instructions)

## Introduction
ML has recently gained a lot of traction in the fields of language modeling and sequential data processing / understanding. There are already [examples of how to use machine learning (Recurrent Neural Network/ RNN) for English language modeling](https://www.wolfram.com/language/12/neural-network-framework/train-a-net-to-model-english.html?product=mathematica) in the Wolfram Documentation. In this project, I take this simple RNN sequential data modeling approach and apply it to slightly more complex music data.

## Howl Library  🐺🎶🎵🎶🎼🎹

[Howl (GitHub link)](https://github.com/alecGraves/Howl) is a Wolfram Language / Mathematica library I made for converting .mid files into sequential musical note numeric data and training ML models on that data. This library has a lot of utilities for loading Midi files, performing data augmentation for training on musical notes, and a ton of other things I needed to complete this project.

The library also has a script called `trainRnn.wls` that I use for training a recurrent network (currently an LSTM net).

See the available functions in the HowlMidiTools library: [(GitHub Link)](https://github.com/alecGraves/Howl/blob/c9b04fedc3874f5c8336c65cca566b9103810bcf/Howl/HowlMidiTools.wl#L20-L45)

## Building your Dataset
Before we can start training, you must gather the data you want to train on. There are several large MIDI file datasets you can use to start with, or you can build a dataset using MIDI songs from your favorite creators around the internet. I built my dataset from a collection of my favorite piano scores from [musescore](https://musescore.com/).

You want a lot of different .mid files so the network you train cannot simply memorize all of your training data and instead has to perform some amount of information generalization. Our data augmentation strategy helps with this, but it will not completely solve the issue of having too little data. I have found that 150 songs is acceptable when using smaller RNNs.

## Converting Dataset to Note Data
Once you have a folder with .mid files, you can use the Howl library to load those midi files and convert them into sequential numeric data.

To load the functions exposed by the Howl library, simply run:

```mathematica
SetDirectory["Howl"]; (* Wherever the git repo is *)
<< "Howl/HowlMidiTools.wl"
```

To generate a dataset for training from a folder containing .mid ("MIDI") files, you can simply run:

```mathematica
datasetPath = "/path/to/my/.mid/files";
dataset = Map[HowlMidiImport, HowlFindMidis[datasetPath]];
Length[dataset]
```

This will take around 3 seconds per midi file, so be sure to save the dataset to a file afterwards:

```mathematica
Export["datset.wxf", dataset]
```
## Training the RNN

Next, I use this dataset file to perform training using [the trainRnn.wls script](https://github.com/alecGraves/Howl/blob/main/Scripts/trainRnn.wls).


First, copy your `dataset.wxf` file to the `Howl/Scripts/` folder of the Howl GitHub project, then run the following in your command line in the same `Howl/Scripts/` folder to perform training:

```bash
wolframscript -f trainRnn.wls
```

I have found that the notebook interface will slow down and crash during training on windows (maybe due to the number of batches or doing cpu-intensive minibatch generation?), so using the wolframscript CLI is highly recommended.

By default, the training time is 12 hours and the training device is set to GPU, but you can change this in the [NetTrain function of the script](https://github.com/alecGraves/Howl/blob/07aed0404159027eeed55414e21a5b9c652998e0/Scripts/trainRnn.wls#L218).

When training is done, the predictor model will be stored in the `checkpoints_xxxx/` folder.


If anyone wants to play with the predictions without going through the training process, you can download my [192-node LSTM network HERE :)][model]



## Output Prediction
After we have our predictor, we then generate audio by first giving our network a random note then repeatedly appending the output of the predictor to the input at the next step.

This is done with the Nest[] function and SequenceLastLayer[] below.

Note: [Pre-trained 192-node LSTM model for download][model]


&[Wolfram Notebook][nb]

Rendering the final audio is done with [Klavier - Gravitas Piano](https://www.audioimperia.com/products/klaviergravitaspiano) from Audio Imperia and the [Kontact 6](https://www.native-instruments.com/en/products/komplete/samplers/kontakt-6/) sampler by Native Instruments - all inside of the [Waveform DAW](https://www.tracktion.com/products/waveform-pro) by Tracktion.


##Conclusions

I hope you find this project useful if you ever want to apply sequence-modeling techniques to more complex multi-output sequences.

Musically, the networks seem to be capable of generating interesting new patterns not found anywhere in their dataset. However, I think the real utility of such models in art is when a human works collaboratively with the algorithm, pausing the output to modify sections and inject their own artistic flair. Seeing what the networks are capable with only random input really gives me hope for them as collaborative tools in the future. Some truly amazing music will come from hybrid human-machine groups.

If anyone has suggestions for more-efficiently generating RNN output (currently I use Nest[] and SequenceLastLayer[]), that would be super appreciated!

Additionally, transformers have the potential to greatly improve training times over the LSTM nets currently used by this project. If anyone here has experience with Transformers in the wolfram language, I would really appreciate it if you could provide a simple example!!

Remember to share the awesome stuff you build!

-Alec

[nb]: https://www.wolframcloud.com/obj/a31570f8-6e37-4618-bd29-b37cd70ced5e
[model]: https://graves.tech/assets/piano/predictor_lstm192_2021-07-25T20-23-31.wlnet 
