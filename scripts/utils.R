library(dplyr)
library(readr)
library(text2vec)
library(magrittr)
library(Rtsne)
library(ggplot2)
id_file <- read_delim("./data/2a_concept_ID_to_string.txt",delim="\t",col_names = FALSE,quote="")
colnames(id_file) <- c("Concept_ID","String")
cui_file <- read_delim("./data/2b_concept_ID_to_CUI.txt",delim="\t",col_names = FALSE,quote="")
colnames(cui_file) <- c("Concept_ID","CUI")

info <- id_file %>% inner_join(cui_file)

#' Compute the mean average precision at k
#'
#' This function computes the mean average precision at k
#' of two lists of sequences.
#'
#' @param k max length of predicted sequence
#' @param actual list of ground truth sets (vectors)
#' @param predicted list of predicted sequences (vectors)
#' @export
#' Adapted from Kaggle: https://github.com/benhamner/Metrics/blob/master/R/R/metrics.r#L181
mapk <- function (k, actual, predicted)
{
  if( length(actual)==0 || length(predicted)==0 ) 
  {
    return(0.0)
  }
  
  scores <- rep(0, length(actual))
  for (i in 1:length(scores))
  {
    scores[i] <- apk(k, actual[[i]], predicted[[i]])
  }
  score <- mean(scores)
  score
}


#' Compute the average precision at k
#'
#' This function computes the average precision at k
#' between two sequences
#'
#' @param k max length of predicted sequence
#' @param actual ground truth set (vector)
#' @param predicted predicted sequence (vector)
#' @export
apk <- function(k, actual, predicted)
{
  score <- 0.0
  cnt <- 0.0
  for (i in 1:min(k,length(predicted)))
  {
    if (predicted[i] %in% actual && !(predicted[i] %in% predicted[0:(i-1)]))
    {
      cnt <- cnt + 1
      score <- score + cnt/i 
    }
  }
  score <- score / min(length(actual), k)
  score
}

#Returns a list of vectors of the embedding sorted by cosine similarity between the vectors and query
get_dist <- function(word_vectors,query,sort_result=TRUE) {
  word_vectors <- as.matrix(word_vectors)
  word_vectors_norm <- sqrt(rowSums(word_vectors^2))
  query_vec <- word_vectors[query,,drop=FALSE]
  cos_dist <- text2vec:::cosine(query_vec, 
                                word_vectors, 
                                word_vectors_norm)
  
  cos_dist <- cos_dist[1,]
  if(sort_result) {
    cos_dist <- sort(cos_dist,decreasing = TRUE)
  }
  return(cos_dist)
}
#Maps CUI to its string 
cuis_to_string <- function(cuis) {
  strings <- info$String[match(cuis,info$CUI)]
  return(strings)
}

#' Load an embedding from a text file.
#' 
#' @param filename File name to be loaded.
#' @param convert_to_cui Should the rownames be mapped from the identifies of Finalyson et al to CUIs?
#' @param header Are there column headers in the file?
#' @param skip How many lines should be skipped?
#' @param delim Delimiter used in file.
#' @return Dataframe containing the embeddings.
load_embeddings <- function(filename,convert_to_cui=FALSE,header=FALSE,skip=1,delim=" ") {
  embeddings <- data.frame(read_delim(filename,delim=delim,skip=skip,col_names = header))
  rownames(embeddings) <- embeddings[,1]
  embeddings <- embeddings[,-1]
  if(convert_to_cui) {
    cuis <- info$CUI[match(rownames(embeddings),info$Concept_ID)]
    rownames(embeddings) <- cuis
  }
  return(data.matrix(embeddings))
}

#Returns the cosine similarity between two vectors.
cos_similairty<- function(vec1,vec2){
  sim <- sum(vec1*t(vec2))/(sqrt(sum(vec1^2))*sqrt(sum(vec2^2)))
  #If vec1 or vec2 is 0, then R normally returns NA because a 0 division error, this catches this 
  if(is.na(sim)){return(0)}
  return(sim)
}

#Computes the DCG for an input vector as compared to the list of truths 
#For an explanation of DCG, see https://en.wikipedia.org/wiki/Discounted_cumulative_gain
dcg <- function(vector, true_list){
  score <- 0 
  cuis <- names(vector)
  relevant_cuis <- which(cuis %in% true_list)
  if (length(relevant_cuis)==0){return(0)}
  for(i in 1:length(relevant_cuis)){
    score <- score + (2^vector[relevant_cuis[i]]-1)/log2(relevant_cuis[i])
  }
  return(score)
}
#Loads comorbidity files
load_comorbidity <- function(filename){
  commorbidity <- read.delim(filename)
  return(commorbidity)
}
#Loads semantic files
load_semantic_type <- function(filename) {
  semantic <- read.delim(filename)
  return(semantic)
}
#Loads causitive files
load_causitive <- function(filename){
  causitive <- read.delim(filename)
  return(causitive)
}
#Loads NDF RT files
load_ndf_rt <- function(filename){
  ndf_rt <- read.delim(filename)
  return(ndf_rt)
}

#This function benchmarks an embedding on all possible benchmarks that use MAP as a metric
#embedding is the embedding you want to benchmark
#ref_embeddings is a list() of embeddings loaded in your local environment. If specified, then
#this benchmark will also benchmark these embeddings
#Ues take_intersection to determine whether the benchmark will benchmark on the intersection of CUIs across all embeddings
benchmark_map <- function(embedding,k,ref_embeddings=NULL,take_intersection=TRUE){
  #Generate the data frame we will return 
  df <- data.frame(test = character(), embedding_name = character(), score = numeric(), stringsAsFactors = FALSE)
  #Reference CUIs are at least the CUIs of the embedding we are benchmarking
  ref_cuis <- rownames(embedding)
  #If the user specified intersection, we intersect over any specified embedding
  if(!is.null(ref_embeddings)&take_intersection){
    for(j in 1:length(ref_embeddings)){
      ref_cuis <- intersect(ref_cuis,rownames(ref_embeddings[[j]]))
    }
  }
  #Benchmark the embedding 
  causitive <- benchmark_causitive(embedding,k,ref_cuis)
  semantic_type <- benchmark_semantic_type(embedding,k,ref_cuis)
  ndf_rt <- benchmark_ndf_rt(embedding,k,ref_cuis)
  comorbidity <- benchmark_comorbidities(embedding, k, ref_cuis, return_max=T, metric='AP')
  
  name <- deparse(substitute(embedding))
  for(i in 1:dim(causitive)[1]){
    df[dim(df)[1]+1,] <- c(paste0('causitive_',causitive[i,1]),name,causitive[i,2])
  }
  for(i in 1:dim(semantic_type)[1]){
    df[dim(df)[1]+1,] <- c(paste0('semantic_type_',semantic_type[i,1]),name,semantic_type[i,2])
  }
  for(i in 1:dim(ndf_rt)[1]){
    df[dim(df)[1]+1,] <- c(paste0('ndf_rt_',ndf_rt[i,1]),name,ndf_rt[i,2])
  }
  for(i in 1:dim(comorbidity)[1]){
    df[dim(df)[1]+1,] <- c(paste0('comorbidity_',paste0(comorbidity[i,1],comorbidity[i,2])),name,comorbidity[i,3])
  }
  
  #Benchmark the reference embeddings
  if(!is.null(ref_embeddings)){
  for(j in 1:length(ref_embeddings)){
    if(!take_intersection){
      #we need to at least take the intersection pairwise between the embedding and reference embeddings
      ref_cuis <- intersect(rownames(embedding,rownames(ref_embeddings[[j]])))
    }
    causitive <- benchmark_causitive(ref_embeddings[[j]],k,ref_cuis)
    semantic_type <- benchmark_semantic_type(ref_embeddings[[j]],k,ref_cuis)
    ndf_rt <- benchmark_ndf_rt(ref_embeddings[[j]],k,ref_cuis)
    comorbidity <- benchmark_comorbidities(ref_embeddings[[j]], k, ref_cuis, return_max=T, metric='AP')
    #users will have to manually change the names of the reference in the final data frame
    #the names are lost when reference embeddings are enclosed in a list()
    name <- paste0('reference_',j)
    for(i in 1:dim(causitive)[1]){
      df[dim(df)[1]+1,] <- c(paste0('causitive_',causitive[i,1]),name,causitive[i,2])
    }
    for(i in 1:dim(semantic_type)[1]){
      df[dim(df)[1]+1,] <- c(paste0('semantic_type_',semantic_type[i,1]),name,semantic_type[i,2])
    }
    for(i in 1:dim(ndf_rt)[1]){
      df[dim(df)[1]+1,] <- c(paste0('ndf_rt_',ndf_rt[i,1]),name,ndf_rt[i,2])
    }
    for(i in 1:dim(comorbidity)[1]){
      df[dim(df)[1]+1,] <- c(paste0('comorbidity_',paste0(comorbidity[i,1],comorbidity[i,2])),name,comorbidity[i,3])
    }
  }
  }
  df$score <- as.numeric(df$score)
return(df)
}

#This function benchmarks an embedding on all possible benchmarks that use DCG as a metric
#embedding is the embedding you want to benchmark
#ref_embeddings is a list() of embeddings loaded in your local environment. If specified, then
#this benchmark will also benchmark these embeddings
#Ues take_intersection to determine whether the benchmark will benchmark on the intersection of CUIs across all embeddings
#return max dictates whether the DCG for all concepts in a file are returned, or just the maximum 
benchmark_dcg<- function(embedding,k,ref_embeddings=NULL,take_intersection=TRUE,return_max=FALSE){
  #Generating the data frame we return 
  df <- data.frame(test = character(), embedding_name = character(), score = numeric(), stringsAsFactors = FALSE)
  #Reference CUIs are at least the CUIs of the embedding we are benchmarking
  ref_cuis <- rownames(embedding)
  #If the user specified intersection, we intersect over any specified embedding
  if(!is.null(ref_embeddings)&take_intersection){
    for(j in 1:length(ref_embeddings)){
      ref_cuis <- intersect(ref_cuis,rownames(ref_embeddings[[j]]))
    }
  }
  #Benchmark the embedding
  comorbidity <- benchmark_comorbidities(embedding, k, ref_cuis,return_max)
  name <- deparse(substitute(embedding))
  for(j in 1:dim(comorbidity)[1]){
      df[dim(df)[1]+1,] <- c(paste(comorbidity[j,1],comorbidity[j,2],sep='_'),name,comorbidity[j,3])
  }
  
  #Benchmark the reference embeddings
  for(j in 1:length(ref_embeddings)){
    if(!take_intersection){
      ref_cuis <- intersect(rownames(embedding,rownames(ref_embeddings[[j]])))
    }
    comorbidity <- benchmark_comorbidities(ref_embeddings[[j]], k, ref_cuis,return_max)
    #users will have to manually change the names of the reference in the final data frame
    #the names are lost when reference embeddings are enclosed in a list()
    name <- paste0('reference_',j)
    for(i in 1:dim(comorbidity)[1]){
      df[dim(df)[1]+1,] <- c(paste(comorbidity[i,1],comorbidity[i,2],sep='_'),name,comorbidity[i,3])
    }
  }
  df$score <- as.numeric(df$score)
  return(df)
}

#Simple ggplot of the data frame that is produced by benchmark_dcg()
visualize_dcg <- function(df){
  rt <- ggplot(data=df, aes(x=test,y=score,color=embedding_name))+geom_point()
  rt <- rt+theme_bw()+theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust=1))
  rt <- rt+labs(title='DCG Benchmark')+labs(x='Test')+labs(y='DCG Score')
  return(rt)
}
#Simple ggplot of the data frame that is prodcued by benchmark_map()
visualize_map <- function(df){
  rt <- ggplot(data=df, aes(x=df$test,y=df$score,color=df$embedding_name))+geom_point()
  rt <- rt+theme_bw()+theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust=1))
  rt <- rt+labs(title='MAP Benchmark of')+labs(x='Test')+labs(y='Mean Average Precision')
  return(rt)
}

#generates a tSNE of an embedding
#defaults the axis names to X1 and X2
#adds a column that keeps track the CUIs for each data point in the tSNE 
get_tsne <- function(embedding,verbose=FALSE){
  tsne <- data.frame(Rtsne(as.matrix(embedding),verbose=verbose)$Y)
  colnames(tsne)<-c('X1','X2')
  tsne$CUI <- rownames(embedding)
  return(tsne)
}

#This function visualizes where the CUIs in a file are located in the tSNE plot 
#if tsne is NULL, this will take much longer to compute 
#file is the path, if not specified the function will return the basic tSNE
#type is one of 'COMORBIDITY', 'CAUSITIVE', 'SEMANTIC_TYPE', 'NDF_RT'
#***This assumes the tSNE dimensions are X1 and X2***
#If you generate the tSNE with get_tsne(), this function will automatically work 
visualize_embedding <- function(embedding,tsne=NULL,file='', type=''){
  type = toupper(type)
  if(is.null(tsne)){
    tsne <- get_tsne(embedding)
  }
  if(file==''){
    df <- tsne
    rt <-ggplot(data=df,aes(x=X1,y=X2))+geom_point()+scale_alpha(.1)+theme_bw()
    return(rt)
  }
  #Get the name of the file 
  name = strsplit(tail(strsplit(file,'/')[[1]],1),'.txt')[[1]]
  if(identical(type,'COMORBIDITY')){
    comorbidity <- load_comorbidity(file)
    df <- tsne
    #Get the valid concepts and associations for the embedding
    concepts <- intersect(comorbidity$CUI[which(comorbidity$Type=='Concept')],rownames(embedding))
    associations <- intersect(comorbidity$CUI[which(comorbidity$Type=='Association')],rownames(embedding))
    df$Type <- 'Background'
    #Match the CUIs that are concepts in the embedding 
    for(cui in concepts){
      df[match(cui,df$CUI),4]<-'Concept'}
    #Match the CUIs that are associations in the embedding
    for(cui in associations){df[match(cui,df$CUI),4]<-'Association'}
    #plot the tSNE
    rt <- ggplot(data = df, aes(x=X1,y=X2,color=Type,alpha=Type))+geom_point()+scale_color_manual(values=c("#E69F00","#999999", "#56B4E9"))+scale_alpha_manual(values = c(1,.1,1))+theme_bw()
    rt <- rt + labs(title=paste(name,'Comorbidity t-SNE'))
    return(rt)
  }
  if(identical(type,'CAUSATIVE')){
    cause <- load_causitive(file)
    df <- tsne
    df$Type <- 'Background'
    #Get the valid concepts and associations
    for(cui in intersect(cause$CUI_Cause,df$CUI)){df[match(cui,df$CUI),4]<-'Cause'}
    for(cui in intersect(cause$CUI_Result,df$CUI)){df[match(cui,df$CUI),4]<-'Result'}
    #Plot the tSNE
    rt <- ggplot(data = df, aes(x=X1,y=X2,color=Type,alpha=Type))+geom_point()+scale_color_manual(values=c("#999999", "#E69F00", "#56B4E9"))+scale_alpha_manual(values = c(.1,1,1))+theme_bw()
    rt <- rt+labs(title=paste(name,'Causitive t-SNE'))
    return(rt)
  }
  if(identical(type,'SEMANTIC_TYPE')){
    semantic_type <- load_semantic_type(file)
    df <- tsne
    #Get the valid CUIs
    cuis <- intersect(semantic_type$CUI,rownames(embedding))
    df$Type <- 'Background'
    #Match the valid CUIs
    for(cui in cuis){df[match(cui,df$CUI),4]<-name}
    #plot the tSNE
    rt <- ggplot(data = df, aes(x=X1,y=X2,color=Type,alpha=Type))+geom_point()+scale_color_manual(values=c("#999999", "#E69F00"))+scale_alpha_manual(values = c(.1,1))+theme_bw()
    rt <- rt+labs(title=paste(name,'Semantic Type t-SNE'))
    return(rt)
  }
  if(identical(type,'NDF_RT')){
    ndfrt <- load_semantic_type(file)
    #Get the valid treatments 
    treatment <- intersect(ndfrt$Treatment,rownames(embedding))
    #Initialize the valid condition list with an empty string 
    condition <- ''
    #Since conditions are stored in a list of condition1, condition2... ; condition1, condition2, condition3...;
    #Just pasting the line to the condition string
    for (i in 1:length(ndfrt$Condition)){
      condition <- paste0(condition, ndfrt$Condition[i])
    }
    #Then split the condition string by commas, getting all the conditions, and finding all valid conditions 
    condition <- intersect(strsplit(condition,','),rownames(embedding))
    df <- tsne
    df$Type <- 'Background'
    #Matching the valid treatments and conditions 
    for(cui in treatment){df[match(cui,df$CUI),4]<-'Treatment'}
    for(cui in condition){df[match(cui,df$CUI),4]<-'Condition'}
    #Plot the tSNE 
    rt <- ggplot(data = df, aes(x=X1,y=X2,color=Type,alpha=Type))+geom_point()+scale_color_manual(values=c("#999999", "#E69F00", "#56B4E9"))+scale_alpha_manual(values = c(.1,1,1))+theme_bw()
    rt <- rt+labs(title=paste(name,'NDF_RT t-SNE'))
    return(rt)
  }
  #No valid type
  return(NULL)
}

#This function marks a tSNE with multiple different files (can be comorbidity or semnatic type files) 
#dir is a directory where all the files are
#names is a list() of the readable names you want the tSNE to be marked with eg 'Genetic Funciton', 'Heart Disease', 'Obesity'
#as opposed to 'genetic_function.txt'
#If you leave names null, they will default to the file names 
populate_tsne <- function(tsne,dir,names=NULL){
  #Counter for the for loop
  i<-1
  #So we don't overwrite anything unfortuante 
  df <- tsne 
  #If there is a Type column, presumably the user wants to maintain the information there 
  if(!('Type' %in% colnames(df))){df$Type <- 'Background'}
  #If there is no CUI list, you should use get_tsne() again 
  if(!('CUI' %in% colnames(df))){return(NULL)}
  #Loop over the files of that are either comorbidity files or semantic type files 
  for(file in list.files(dir)){
    comor <- load_comorbidity(paste(dir,file,sep='/'))
    #Get the valid cuis 
    cuis <- intersect(comor$CUI,df$CUI)
    name <- names[i]
    if(is.null(names)){name<-strsplit(file,'.txt')}
    #match the valid cuis and indicate their type 
    for(cui in cuis){if(comor$Type[match(cui,comor$CUI)]=='Association'){df$Type[match(cui,df$CUI)]<-name}}
    #move the counter 
    i<-i+1
  }
  return(df)
}

#Converts the top k vectors for a worb embedding back into English 
top_k_vis <- function(query, embedding, k){
  if(!(query %in% rownames(embedding))){
    print('CUI not in embedding')
    return(NULL)
  }
  print(paste('Conversion for',query,info$String[match(query,info$CUI)]))
  cos <- get_dist(embedding, query)[1:k]
  cuis <- names(cos)
  words <- info$String[match(cuis,info$CUI)]
  return(cbind(words,cos))
}
