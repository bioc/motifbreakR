#' Import SNPs from rsid for use in motifbreakR
#'
#' @param rsid Character; a character vector of rsid values from dbSNP
#' @param dbSNP an object of class SNPlocs to lookup rsids; see \code{availible.SNPs} in
#'   \code{\link[BSgenome]{injectSNPs}} to check for availible SNPlocs
#' @param search.genome an object of class BSgenome for the species you are interrogating;
#'  see \code{\link[BSgenome]{available.genomes}} for a list of species.
#' @param biomart.dataset a Mart object from \code{\link{useEnsembl}} specifying
#'  the \code{snps} biomart, which dataset i.e., \code{hsapiens_snp}, and which
#'  version i.e., \code{111} or \code{GRCm39}. This will override \code{SNPlocs} and must
#'  be compatible with search.genome selection, and will query from \code{biomaRt},
#'  which may be considerably faster than a lookup from a \code{SNPlocs} object.
#' @seealso See \code{\link{motifbreakR}} for analysis; See \code{\link{snps.from.file}}
#'   for an alternate method for generating a list of variants.
#' @details \code{snps.from.rsid} take an rsid, or character vector of rsids and
#'  generates the required object to input into \code{motifbreakR}
#' @return a GRanges object containing:
#'  \item{SNP_id}{The rsid of the snp with the "rs" portion stripped}
#'  \item{alleles_as_ambig}{THE IUPAC ambiguity code between the reference and
#'  alternate allele for this SNP}
#'  \item{REF}{The reference allele for the SNP}
#'  \item{ALT}{The alternate allele for the SNP}
#' @examples
#'  library(BSgenome.Hsapiens.UCSC.hg19)
#'  library(SNPlocs.Hsapiens.dbSNP155.GRCh37)
#'  snps.file <- system.file("extdata", "pca.enhancer.snps", package = "motifbreakR")
#'  snps <- as.character(read.table(snps.file)[,1])
#'  snps.mb <- snps.from.rsid(snps[1],
#'                            dbSNP = SNPlocs.Hsapiens.dbSNP155.GRCh37,
#'                            search.genome = BSgenome.Hsapiens.UCSC.hg19)
#'
#'  ## alternatively using biomaRt
#'
#'  library(biomaRt)
#'  library(BSgenome.Hsapiens.UCSC.hg38)
#'  ensembl_snp <- useEnsembl(biomart = "snps",
#'                            dataset = "hsapiens_snp",
#'                            version = "112")
#'  snps.mb <- snps.from.rsid(snps,
#'                            biomart.dataset = ensembl_snp,
#'                            search.genome = BSgenome.Hsapiens.UCSC.hg38)
#'
#' @importFrom BSgenome snpsById snplocs snpsByOverlaps
#' @importFrom Biostrings DNAStringSet DNAString DNAStringSetList
#' @importFrom biomaRt useEnsembl getBM searchDatasets
#' @export
snps.from.rsid <- function(rsid = NULL, dbSNP = NULL,
                           search.genome = NULL,
                           biomart.dataset = NULL) {
  if (is.null(rsid)) {
    stop("no RefSNP IDs have been found, please include RefSNP ID numbers")
  }
  if (!inherits(search.genome, "BSgenome")) {
    stop(paste0("search.genome argument was not provided with a valid BSgenome object.\n",
                "Run availible.genomes() and choose the appropriate BSgenome object"))
  }
  if (all(!grepl("rs", rsid))) {
    bad.names <- rsid[!grepl("rs", rsid)]
    stop(paste(paste(bad.names, collapse = " "), "are not rsids, perhaps you want to import your snps from a bed or vcf file with snps.from.file()?"))
  }
  rsid <- unique(rsid)
  if (!is.null(biomart.dataset)) {
    ens.genome <- searchDatasets(biomart.dataset, pattern = biomart.dataset@dataset)$version[[1]]
    ens.genome <- Seqinfo(genome = ens.genome)
    ens.seqlevel <- seqnames(keepStandardChromosomes(ens.genome))
    seqlevelsStyle(ens.genome) <- seqlevelsStyle(search.genome)
    compatible_genome <- genome(ens.genome)[[1]] == genome(search.genome)[[1]]
    if(!compatible_genome) stop("bioMart genome and BSgenome are not compatible")
    bm.snp <- getBM(attributes = c('refsnp_id','chr_name','chrom_start','chrom_end','allele'),
                    filters = c("snp_filter", "chr_name"),
                    values = list(rsid, ens.seqlevel),
                    mart = biomart.dataset)
    bm.snp <- biomartToGranges(bm.snp, biomart.dataset)
    bm.snp <- sort(formatVcfOut(bm.snp, search.genome))
    return(bm.snp)
  }
  if (!inherits(dbSNP, "SNPlocs")) {
    stop(paste0("dbSNP argument was not provided with a valid SNPlocs object.\n",
                "Please run availible.SNPs() to check for availible SNPlocs"))
  }
  rsid.grange <- as(snpsById(dbSNP, rsid, ifnotfound = "warning"), "GRanges")
  rsid.grange <- change.to.search.genome(rsid.grange, search.genome)
  rsid.grange <- GRanges(rsid.grange)
  rsid.refseq <- getSeq(search.genome, rsid.grange)
  rsid.grange$UCSC.reference <- as.character(rsid.refseq)
  rsid.grange <- sapply(split(rsid.grange, rsid.grange$RefSNP_id), function(snp) {
    alt.allele <- determine.allele.from.ambiguous(snp$alleles_as_ambig, snp$UCSC.reference)
    if (length(alt.allele) > 1L) {
      snp <- do.call("c", replicate(length(alt.allele), snp))
      snp$UCSC.alternate <- alt.allele
      names(snp) <- paste(snp$RefSNP_id, alt.allele, sep = ":")
    } else {
      snp$UCSC.alternate <- alt.allele
      names(snp) <- snp$RefSNP_id
    }
    return(snp)
  })
  rsid.grange <- unlist(do.call("GRangesList", rsid.grange), use.names = FALSE)
  colnames(mcols(rsid.grange)) <- c("RefSNP_id", "alleles_as_ambig", "REF", "ALT")
  rsid.grange$REF <- DNAStringSet(rsid.grange$REF)
  rsid.grange$ALT <- DNAStringSet(rsid.grange$ALT)
  # rsid.grange$alleles_as_ambig <- DNAStringSet(rsid.grange$alleles_as_ambig)
  rsid.grange$alleles_as_ambig <- NULL
  colnames(mcols(rsid.grange))[1] <- "SNP_id"
  attributes(rsid.grange)$genome.package <- attributes(search.genome)$pkgname
  return(rsid.grange)
}

determine.allele.from.ambiguous <- function(ambiguous.allele, known.allele) {
  neucleotide.ambiguity.code <- list(Y = c("C", "T"), R = c("A", "G"), W = c("A", "T"),
                                     S = c("G", "C"), K = c("T", "G"), M = c("C", "A"),
                                     D = c("A", "G", "T"), V = c("A", "C", "G"),
                                     H = c("A", "C", "T"), B = c("C", "G", "T"),
                                     N = c("A", "C", "G", "T"))
  specnac <- neucleotide.ambiguity.code[[ambiguous.allele]]
  unknown.allele <- specnac[-grep(known.allele, specnac)]
  return(unknown.allele)
}

#' @import GenomeInfoDb
#' @importFrom stringr str_extract
change.to.search.genome <- function(granges.object, search.genome) {
  if (all(!is.na(genome(granges.object)))) {
    if (identical(genome(granges.object), genome(search.genome))) {
      return(granges.object)
    }
  }
  if(isTRUE(all.equal(seqlevels(granges.object), seqlevels(search.genome)))) {
    seqinfo(granges.object) <- seqinfo(search.genome)
  } else {
    if(!all(seqlevelsStyle(granges.object) %in% seqlevelsStyle(search.genome))) {
      seqlevelsStyle(granges.object) <- seqlevelsStyle(search.genome)
    }
    normal.xome <- seqlevels(granges.object)[(regexpr("_", seqlevels(granges.object)) < 0)]
    positions <- unlist(sapply(paste0("^", normal.xome, "$"), grep, seqnames(seqinfo(search.genome))))
    new2oldmap <- rep(NA, length(seqinfo(search.genome)))
    new2oldmap[positions] <- seq_len(length(positions))
    seqinfo(granges.object, new2old = new2oldmap) <- seqinfo(search.genome)
  }
  granges.object <- keepStandardChromosomes(granges.object, pruning.mode = "coarse")
  return(granges.object)
}

biomartToGranges <- function(bm.snp, biomart.dataset) {
  bm.snp$split_id <- factor(bm.snp$refsnp_id)
  bm.snp <- bm.snp[order(bm.snp$split_id),]
  allele <- strsplit(bm.snp$allele, split = "/")
  snps.ref <- vapply(allele,
                     function(x) {
                       x[[1]]
                     }, character(1))
  snps.alt.split <- Map(f = function(x,y) {
    x[2:y]
  }, allele, lengths(allele))
  bm.snp <- split(bm.snp, bm.snp$refsnp_id)
  rep.vars <- vapply(snps.alt.split, length, integer(1))
  bm.snp <- rep(bm.snp, rep.vars)
  snps.ref <- rep(snps.ref, rep.vars)
  snps.alt <- unlist(snps.alt.split)
  bm.snp <- do.call(rbind, bm.snp)
  bm.snp$SNP_id <- bm.snp$refsnp_id
  bm.snp$REF <- snps.ref
  bm.snp$ALT <- snps.alt
  ens.genome <- searchDatasets(biomart.dataset, pattern = biomart.dataset@dataset)$version[[1]]
  ens.genome <- Seqinfo(genome = ens.genome)
  bm.snp <- with(bm.snp, GRanges(seqnames = chr_name,
                                 ranges = IRanges(start = chrom_start,
                                                  end = chrom_end),
                                 SNP_id = SNP_id,
                                 REF = DNAStringSet(REF),
                                 ALT = DNAStringSet(ALT),
                                 seqinfo = ens.genome))
  # browser()
  bm.snp <- keepSeqlevels(bm.snp, value = unique(as.character(runValue(seqnames(bm.snp)))), pruning.mode = "coarse")
  names(bm.snp) <- bm.snp$SNP_id
  return(bm.snp)
}

strSort <- function(x) {
  sapply(lapply(strsplit(x, NULL), sort), paste, collapse = "")
}

unlistColumn <- function(x, column = NULL) {
  if (is.null(column)) {
    stop("select column to unlist from x")
  }
  if (is(mcols(x)[[column]], "DNAStringSet")) {
    mcols(x)[[column]] <- as.character(mcols(x)[[column]])
  }
  if (is(mcols(x)[[column]], "DNAStringSetList") & all(lengths(mcols(x)[[column]]) == 1)) {
    mcols(x)[[column]] <- as.character(unlist(mcols(x)[[column]]))
  }
  if (any(lengths(mcols(x)[[column]]) > 1)) {
    columnvals <- unlist(mcols(x)[[column]])
    numsplits <- lengths(mcols(x)[[column]])
    x <- rep(x, times = numsplits)
    mcols(x)[[column]] <- columnvals
    return(x)
  } else {
    return(x)
  }
}

formatVcfOut <- function(x, gseq) {
  x$SNP_id <- names(x)
  mcols(x) <- mcols(x)[, c("SNP_id", "REF", "ALT")]
  x$REF <- unlist(DNAStringSetList(x$REF))
  x$ALT <- unlist(DNAStringSetList(x$ALT))
  x <- keepStandardChromosomes(x, pruning.mode = "coarse")
  seqlevelsStyle(x) <- seqlevelsStyle(gseq)
  seqlevels(x) <- mapSeqlevels(seqlevels(x), seqlevelsStyle(gseq))
  x <- change.to.search.genome(x, gseq)
  can.ref <- getSeq(gseq, x)
  names(can.ref) <- NULL
  if (all(can.ref == x$REF)) {
    rm(can.ref)
  } else {
    warning(paste0("User selected reference allele differs from the sequence in ",
                   attributes(gseq)$pkgname, " continuing with genome specified",
                   " reference allels\n", "there are ", sum(x$REF != can.ref),
                   " differences"))
  }
  attributes(x)$genome.package <- attributes(gseq)$pkgname
  return(x)
}

#' Import SNPs from a BED file or VCF file for use in motifbreakR
#'
#' @param file Character; a character containing the path to a bed file or a vcf file
#'   see Details for a description of the required format
#' @param dbSNP OPTIONAL; an object of class SNPlocs to lookup rsids; see \code{availible.SNPs} in
#'   \code{\link[BSgenome]{injectSNPs}} to check for availible SNPlocs
#' @param search.genome an object of class BSgenome for the species you are interrogating;
#'  see \code{\link[BSgenome]{available.genomes}} for a list of species
#' @param format Character; one of \code{bed} or \code{vcf}
#' @param indels Logical; allow the import of indels.
#' @param biomart.dataset a Mart object from \code{\link{useEnsembl}} specifying
#'  the \code{snps} biomart, which dataset i.e., \code{hsapiens_snp}, and which
#'  version i.e., \code{111} or \code{GRCm39}. This will override \code{SNPlocs} and must
#'  be compatible with search.genome selection, and will query from \code{biomaRt},
#'  which may be considerably faster than a lookup from a \code{SNPlocs} object.
#' @param check.unnamed.for.rsid Logical; check snps in the form chr:pos:ref:alt
#'  for corresponding rsid, lookup may be slow, requires either param dbSNP or biomart.dataset.
#' @seealso See \code{\link{motifbreakR}} for analysis; See \code{\link{snps.from.rsid}}
#'   for an alternate method for generating a list of variants.
#' @details \code{snps.from.file} takes a character vector describing the file path
#'  to a bed file that contains the necissary information to generate the input for
#'  \code{motifbreakR} see \url{http://www.genome.ucsc.edu/FAQ/FAQformat.html#format1}
#'  for a complete description of the BED format.  Our convention deviates in that there
#'  is a required format for the name field.  \code{name} is defined as chromosome:start:REF:ALT
#'  or the rsid from dbSNP (if you've included the optional SNPlocs argument).
#'  For example if you were to include rs123 in it's alternate
#'  format it would be entered as chr7:24966446:C:A
#' @return a GRanges object containing:
#'  \item{SNP_id}{The rsid of the snp with the "rs" portion stripped}
#'  \item{alleles_as_ambig}{THE IUPAC ambiguity code between the reference and
#'  alternate allele for this SNP}
#'  \item{REF}{The reference allele for the SNP}
#'  \item{ALT}{The alternate allele for the SNP}
#' @examples
#'  library(BSgenome.Drerio.UCSC.danRer7)
#'  library(SNPlocs.Hsapiens.dbSNP155.GRCh37)
#'  snps.bed.file <- system.file("extdata", "danRer.bed", package = "motifbreakR")
#'  # see the contents
#'  read.table(snps.bed.file, header = FALSE)
#'  #import the BED file
#'  snps.mb <- snps.from.file(snps.bed.file,
#'                            search.genome = BSgenome.Drerio.UCSC.danRer7,
#'                            format = "bed")
#'
#' @importFrom rtracklayer import export.bed
#' @importFrom Biostrings IUPAC_CODE_MAP uniqueLetters BStringSetList DNA_ALPHABET
#' @importFrom VariantAnnotation readVcf ref alt isSNV VcfFile ScanVcfParam
#' @importFrom SummarizedExperiment rowRanges
#' @importFrom stringr str_sort str_split
#' @export
snps.from.file <- function(file = NULL, dbSNP = NULL, search.genome = NULL, format = "bed", indels = FALSE, biomart.dataset = NULL, check.unnamed.for.rsid = FALSE) {
  if (format == "vcf") {
    if (!inherits(search.genome, "BSgenome")) {
      stop(paste0(search.genome, " is not a BSgenome object.\n", "Run availible.genomes() and choose the appropriate BSgenome object"))
    }
    genome.name <- genome(search.genome)[[1]]
    vcfparam <- ScanVcfParam(info = NA, geno = NA)
    vcffile = open(VcfFile(file))
    vcf = readVcf(vcffile, genome = genome.name, param = vcfparam)
    close(vcffile)
    vcf_ranges <- rowRanges(vcf)
    vcf_ranges <- unlistColumn(vcf_ranges, "ALT")
    vcf_ranges <- unlistColumn(vcf_ranges, "REF")
    vcf_ranges$index <- seq_along(vcf_ranges)
    complex.variants <- vcf_ranges[nchar(vcf_ranges$REF) > 1 | nchar(vcf_ranges$ALT) > 1]
    snps <- vcf_ranges[!(nchar(vcf_ranges$REF) > 1 | nchar(vcf_ranges$ALT) > 1)]
    if (indels) {
      if (length(complex.variants) > 0) {
        alt_letters <- uniqueLetters(unlist(BStringSetList(complex.variants$ALT)))
        ref_letters <- uniqueLetters(unlist(BStringSetList(complex.variants$REF)))
        alt_letters_remove <- alt_letters[!alt_letters %in% DNA_ALPHABET]
        ref_letters_remove <- ref_letters[!ref_letters %in% DNA_ALPHABET]
        if (length(alt_letters_remove) > 0) {
          search.pattern <- paste0(alt_letters_remove, collapse = "|")
          drop.variants.alt <- vapply(complex.variants$ALT,
                                      function(x,
                                               remove_letters = search.pattern) {
                                        any(grepl(remove_letters, x))
                                      }, logical(1))
        } else {
          drop.variants.alt <- as.logical(rep.int(0, length(complex.variants)))
        }
        if (length(ref_letters_remove) > 0) {
          search.pattern <- paste0(ref_letters_remove, collapse = "|")
          drop.variants.ref <- vapply(complex.variants$REF,
                                      function(x,
                                               remove_letters = search.pattern) {
                                        any(grepl(remove_letters, x))
                                      }, logical(1))
        } else {
          drop.variants.ref <- as.logical(rep.int(0, length(complex.variants)))
        }
        complex.variants <- complex.variants[!(drop.variants.alt | drop.variants.ref)]
        complex.variants <- unlistColumn(complex.variants, "ALT")
        complex.variants <- unlistColumn(complex.variants, "REF")
      }
      all.variants <- c(complex.variants, snps)
      all.variants <- formatVcfOut(all.variants[order(all.variants$index), ], search.genome)
      return(all.variants)
    } else {
      snps <- formatVcfOut(snps, search.genome)
      return(snps)
    }
  } else {
    if (format == "bed") {
      snps <- import(file, format = "bed")
      if (any(grepl("rs", snps$name)) & !((!inherits(dbSNP, "SNPlocs")) | (!inherits(biomart.dataset, "Mart")))) {
        stop(paste0(file, " contains at least one variant with an rsID and no SNPlocs has been indicated\n",
                    "Please run availible.SNPs() to check for availble SNPlocs"))
      }
      if (!inherits(search.genome, "BSgenome")) {
        stop(paste0(search.genome, " is not a BSgenome object.\n", "Run availible.genomes() and choose the appropriate BSgenome object"))
      }
      ## spit snps into named and unnamed snps
      snps.noid <- snps[!grepl("rs", snps$name), ]
      snps.rsid <- snps[grepl("rs", snps$name), ]
      ## get ref for unnamed snps
      snps.ref <- getSeq(search.genome, snps.noid)
      snps.ref <- as.character(snps.ref)
      ## get alt for unnamed snps
      snps.alt <- snps.noid$name
      snps.alt <- unlist(lapply(snps.alt, strsplit, split = ":"), recursive = FALSE)
      snps.ref.user <- sapply(snps.alt, "[", 3)
      if (isTRUE(all.equal(snps.ref, snps.ref.user))) {
        rm(snps.ref.user)
      } else {
        warning(paste0("User selected reference allele differs from the sequence in ",
                       attributes(search.genome)$pkgname, " continuing with genome specified",
                       " reference allels\n", " there are ", sum(snps.ref != snps.ref.user),
                       " differences"))
      }
      snps.alt <- sapply(snps.alt, "[", 4)
      snps.alt.split <- str_split(snps.alt, ",")
      rep.vars <- vapply(snps.alt.split, length, integer(1))
      snps.noid <- rep(snps.noid, rep.vars)
      snps.ref <- rep(snps.ref, rep.vars)
      snps.alt <- unlist(snps.alt.split)
      is.indel <- nchar(snps.alt) > 1 | nchar(snps.ref) > 1
      if (!indels) {
        snps.noid <- snps.noid[!is.indel]
        snps.ref <- snps.ref[!is.indel]
        snps.alt <- snps.alt[!is.indel]
      }
      alt.letters <- uniqueLetters(unlist(BStringSetList(snps.alt)))
      alt_letters_remove <- alt.letters[!alt.letters %in% DNA_ALPHABET]
      if (length(alt_letters_remove) > 0) {
        search.pattern <- paste0(alt_letters_remove, collapse = "|")
        drop.variants.alt <- vapply(complex.variants$ALT,
                                    function(x,
                                             remove_letters = search.pattern) {
                                      any(grepl(remove_letters, x))
                                    }, logical(1))
      } else {
        drop.variants.alt <- as.logical(rep.int(0, length(snps.alt)))
      }
      ## check if alt was given for unnamed snps
      alt.allele.is.valid <- !drop.variants.alt & (snps.alt != snps.ref)
      if (!all(alt.allele.is.valid)) {
        snpnames <- snps.noid$name[drop.variants.alt]
        if (length(snpnames) < 50 && length(snpnames) > 0) {
          warning(paste("User variant", snpnames, "alternate allele is not one of \"A\", \"T\", \"G\", or \"C\""))
        } else {
          if (length(snpnames) > 0) {
            warning(paste0(length(snpnames), " user variants contain an alternate allele that is not one of \"A\", \"T\", \"G\", \"C\"\n",
                           " These variants were excluded"))
          }
        }
        equal.to.ref <- snps.alt == snps.ref
        if (sum(equal.to.ref) > 0) {
          warning(paste0(sum(equal.to.ref), " user variants are the same as the reference genome ",
                         metadata(search.genome)$genome, " for ", metadata(search.genome)$common_name, "\n These variants were excluded"))
        }
        snps.noid <- snps.noid[alt.allele.is.valid]
        snps.ref <- snps.ref[alt.allele.is.valid]
        snps.alt <- snps.alt[alt.allele.is.valid]
      }
      snps.noid$REF <- snps.ref
      snps.noid$ALT <- snps.alt
      strand(snps.noid) <- "*"
      names(snps.noid) <- paste(as.character(snps.noid), snps.ref, snps.alt, sep = ":")
      if(check.unnamed.for.rsid) {
        if(is.null(biomart.dataset)){
          snps.noid <- change.to.search.genome(snps.noid, dbSNP)
          snps.actually.name <- GRanges(snpsByOverlaps(dbSNP, snps.noid, drop.rs.prefix = FALSE))
          which.actually.name <- findOverlaps(snps.actually.name, snps.noid)
        } else {
          ens.genome <- searchDatasets(biomart.dataset, pattern = biomart.dataset@dataset)$version[[1]]
          ens.genome <- Seqinfo(genome = ens.genome)
          seqlevelsStyle(snps.noid) <- seqlevelsStyle(ens.genome)
          snps.noid.original <- snps.noid
          snps.noid <- as.character(snps.noid)
          snps.noid.add.end <- snps.noid[attr(regexpr(":", snps.noid), "match.length") < 2]
          snps.noid.keep <- snps.noid[!(attr(regexpr(":", snps.noid), "match.length") < 2)]
          snps.noid.add.end <- strsplit(snps.noid.add.end, ":")
          snps.noid.add.end <- vapply(snps.noid.add.end, function(x) { paste(x[1], x[2], x[2], sep = ":")}, FUN.VALUE = character(1))
          snps.noid <- c(snps.noid.keep, snps.noid.add.end)
          rm(snps.noid.add.end, snps.noid.keep)
          seqlevelsStyle(ens.genome) <- seqlevelsStyle(search.genome)
          compatible_genome <- genome(ens.genome)[[1]] == genome(search.genome)[[1]]
          if(!compatible_genome) stop("bioMart genome and BSgenome are not compatible")
          bm.snp <- getBM(attributes = c('refsnp_id','chr_name','chrom_start','chrom_end','allele'),
                          filters = c("chromosomal_region"),
                          values = list(snps.noid),
                          mart = biomart.dataset)
          bm.snp <- biomartToGranges(bm.snp, biomart.dataset)
          bm.snp <- subsetByOverlaps(bm.snp, snps.noid.original, type = "equal")
          ohits <- findOverlaps(bm.snp, snps.noid.original, type = "equal")
          snp.add.id <- snps.noid.original[subjectHits(ohits)]$ALT == bm.snp[queryHits(ohits)]$ALT
          snps.actually.name <- bm.snp
          snps.actually.name$RefSNP_id <- snps.actually.name$SNP_id
          which.actually.name <- ohits[snp.add.id]
          snps.noid <- snps.noid.original; rm(snps.noid.original)
        }
        if(length(which.actually.name) > 0) {
          if(length(which.actually.name) < 50) {
            warning(paste0(snps.actually.name[queryHits(which.actually.name)]$RefSNP_id,
                           " was found as a match for ",
                           snps.noid[subjectHits(which.actually.name),]$name,
                           "; using entry from dbSNP\n  "))
          } else {
            warning(length(which.actually.name), " variants had names replaced using entries from dbSNP")
          }
          snps.noid[subjectHits(which.actually.name),]$name <- snps.actually.name[queryHits(which.actually.name)]$RefSNP_id
          snps.noid <- change.to.search.genome(snps.noid, search.genome)
          names(snps.noid) <- snps.noid$name
        } else {
          snps.noid <- change.to.search.genome(snps.noid, search.genome)
        }
      }
      snps.noid <- formatVcfOut(snps.noid, search.genome)
      ## get object for named snps
      if (length(snps.rsid) > 0) {
        snps.rsid.out <- snps.from.rsid(snps.rsid$name, dbSNP = dbSNP, search.genome = search.genome, biomart.dataset = biomart.dataset)
        colnames(mcols(snps.rsid.out))[1] <- "SNP_id"
        names(snps.rsid.out) <- snps.rsid.out$SNP_id
        snps.out <- c(snps.rsid.out, snps.noid)
      } else {
        snps.out <- snps.noid
      }
      attributes(snps.out)$genome.package <- attributes(search.genome)$pkgname
      return(sort(snps.out))
    } else {
      stop("format must be one of 'vcf' or 'bed'; currently set as ", format)
    }
  }
}

#' @describeIn snps.from.file Allows the use of indels by default
#' @export
variants.from.file <- function(file = NULL, dbSNP = NULL, search.genome = NULL, biomart.dataset = NULL, format = "bed") {
  return(snps.from.file(file = file, dbSNP = dbSNP, search.genome = search.genome, format = format, biomart.dataset = biomart.dataset, indels = TRUE))
}
