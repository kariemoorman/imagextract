
<h2 align='center'>imagextract</h2>
 
<p align='center'><img src="diagram.png" alt="diagram" width='60%'/></p>  



<p align='center' style='margin:1'>A MacOS command-line application for extracting text, objects, and faces from image files using Apple Vision and CoreML APIs.</p>

---




## Installation 

Imagextract requires Mac OS version 13 or greater to access the latest VisionKit APIs.

1. Open Terminal
2. Run the following `curl` command:

```bash
curl -L https://github.com/kariemoorman/imagextract/raw/main/install.sh | bash
```
3. Reload terminal configuration file to incorporate new PATHs:

For ZShell users, 
```bash
source ~/.zshrc
```

 For Bash users,
```bash
source ~/.bashrc
```


## Usage

```bash
imagextract IMAGE_FILE.[png|jpg|jpeg|pdf|tiff]
```

### Example

<img src="example/example.png" alt="Example"  />


Output: [imagextract: Proof of Concept](example/README.md)



## License 

MIT



## Contributions

Contributions are welcome. Please submit an issue or feel free to fork and contribute a pull request.


## Acknowledgements

Inspired by projects such as [Textra](https://github.com/freedmand/textra) by [Dylan Freedman](https://github.com/freedmand) and [ObjectDetection-CoreML](https://github.com/tucan9389/ObjectDetection-CoreML) by [tucan9389](https://github.com/tucan9389).
