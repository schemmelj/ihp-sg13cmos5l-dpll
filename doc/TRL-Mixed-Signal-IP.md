# Mixed-Signal IP Quality Assessment using TRL scale

The provided set of the quality assessment criteria, using TRL (Technology Readiness Level) scale, is a tool for designers to auto evaluate a submitted design. The purpose of this tool is to
have a short overview of IP in terms of its maturity.

---

## TRL1 - Basic principles observed

- [x] Is the IP functionality clearly described?
- [x] Is the IP principle of operation explained in detail?
- [x] Are the IP architecture design equations fully listed?
- [x] Do authors supply any mixed-signal HDL functional model (e.g. Verilog-A) of the IP?
- [x] Are functional simulation results of the IP reported for a typical case?

## TRL2 - Concept formulation

- [x] Is the IP architecture described at block level?
- [x] Are the specifications of each individual block of the IP architecture clearly identified?
- [x] If the IP architecture can be configured by means of internal registers, is their mapping declared?
- [x] Do authors supply a complete test bench to validate the IP block-level architecture?
- [x] Is any verification procedure given to check the IP block-level performance figures?
- [x] Are architectural simulation results of the IP reported for a typical case?

## TRL3 - Proof of concept at schematic level

- [x] Are the IP schematics available at transistor level (analog parts) and gate level (digital parts)?
- [x] Are all dependencies of the IP schematics on logic libraries declared?
- [x] Are the analog IP ports fully specified at electrical level?
- [x] Are the digital IP ports fully specified at logical level (e.g. protocols)?
- [x] Do authors supply a mixed-signal test bench to validate the IP schematics?
- [x] Is any verification procedure given to check the IP schematic performance figures?
- [x] Are mixed-signal simulation results of the IP schematics reported for a typical case?

## TRL4 - Full design at schematic level

- [x] Are the mixed-signal simulation results of the IP schematics extended to process, supply and temperature (PVT) corners?
- [x] Are the mixed-signal simulation results of the IP schematics extended to technology mismatching?
- [x] Are the authors defining the mixed-signal supply domains of the IP schematics and their individual power requirements?
- [x] Does the IP description include any power consumption model (e.g. as a function of input stimuli)?

## TRL5 - Full design at layout level

- [x] Is the IP complete layout available?
- [x] Are all dependencies of the IP layout on logic libraries declared?
- [x] Do authors supply a clean DRC report?
- [x] Do authors supply a clean LVS report?
- [x] Are post-layout mixed-signal simulation results of the IP layout reported for PVT corners?

## TRL6 - Full design for SoC integration

- [ ] Does the IP come with suitable descriptors for digital-on-top integration (e.g. Liberty, LEF)?
- [ ] Is the IP incorporating any BIST mechanism? If so, is it properly documented?
- [ ] Does the IP document fully define its digital interface?

## TRL7 - Lab demonstrator prototype

- [ ] Has any dedicated test chip been designed for the hard IP?
- [ ] Is the hard IP test chip fully documented (e.g. pad ring)?
- [ ] Are experimental results available from the IP dedicated test chip (Silicon proven)?
- [ ] Do authors supply any comprehensive comparison between IP test chip and post-layout results?

## TRL8 - In-field demonstrator prototype

- [ ] Has the hard IP been integrated in a SoC context?
- [ ] Are experimental IP results available from this SoC (Silicon proven)?
- [ ] Do authors supply any comprehensive comparison between IP SoC and test-chip results?

## TRL9 - Commercial application

- [ ] Are the IP authors providing support for bug fixing or enhancement requests?
- [ ] Does the IP documentation include any training materials?
- [ ] Are the EDA tools and versions used for developing the IP documented?
- [ ] Is the hard IP integrated in any commercial IC?
