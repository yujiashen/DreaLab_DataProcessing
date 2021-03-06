library(readxl)
library(tidyverse)
library(gdata)
library(purrr)
library(gsubfn)
library(hms)
library(lubridate)
library(data.table)
library(openxlsx)

newlist <- list()
n = 0

shortlst <- lapply(2:59, function(i) as.data.frame(read_excel("data/Pup8MoIndividual_copy_for_ys.xlsx", sheet = i)))
names(shortlst) <- 2:59

for(i in shortlst) {
  n = n + 1
  if(grepl("1899-12-31", i$Time...2) == FALSE & i$Time...2 < 1) {
    i$Time...2 <- round(as.numeric(i$Time...2) * 86400)
    i$Time...2 <- as_hms(i$Time...2)
  } else {
    i$Time...2 <- gsub("1899-12-31 ", "", i$Time...2)
    i$Time...2 <- as_hms(i$Time...2)
  }

  data <- i %>% rename(St.Time = "Time...2", Behavior = "Behavior/Category", AggSub = "Aggression/Submission", Pupcare = "Pup care") %>%
    rename_at(vars(ends_with('focal individual')), ~"Focal individual")

  data$Play <- as.character(data$Play)
  data$AggSub <- as.character(data$AggSub)
  data$Olfactory <- as.character(data$Olfactory)

  data <- data %>%
    mutate(End.Time = as.numeric(NA), .after = "St.Time") %>%
    mutate(End.Sec = as.numeric(NA), .after = "End.Time") %>%
    mutate(Duration = as.numeric(NA), .after = "End.Sec") %>%
    mutate(St.Sec = as.numeric(data$St.Time), .after = "St.Time") %>%
    mutate(OG_order = seq.int(nrow(data))) %>%
    mutate(CHECK = NA) %>%
    mutate(removerow = NA)

  ## ----Focal.ID-------------------------------------------------------------------------------------------------------------------------------------------------------------
  data <- data %>%
    #Get focal indiv name between parentheses
    mutate(KMP.ID = gsub("(?<=\\()[^()]*(?=\\))(*SKIP)(*F)|.", "", `Focal individual`, perl=T)) %>%
    #Fill rest of column with previous KMP.ID
    fill(KMP.ID) %>%
    mutate(Location = case_when(grepl("Burrow", `Focal individual`) & !grepl("Forage", `Focal individual`) ~ "Burrow",
                                grepl("Forage", `Focal individual`) & !grepl("Burrow", `Focal individual`) ~ "Forage",
                                grepl("Burrow", `Focal individual`) & grepl("Forage", `Focal individual`) ~ "Burrow; Forage")) %>%
    mutate(month = month(Date)) %>%
    mutate(is_Start = ifelse(grepl("Start focal", Behavior), TRUE, FALSE)) %>%
    #When a new Start focal appears, iterate the focal number
    mutate(focalnum = ifelse(is_Start == TRUE, 0 + cumsum(is_Start == TRUE), 0 + cumsum(is_Start == TRUE))) %>%
    unite(Focal.ID, month, focalnum, KMP.ID, sep = ".", remove = FALSE) %>%
    relocate(Focal.ID) %>%
    relocate(Location, .after = `Focal individual`) %>%
    select(-is_Start, -month, -focalnum)
  ## ----Pup-care-------------------------------------------------------------------------------------------------------------------------------------------------------------
  data <- data %>%
    mutate(CHECK = ifelse(!is.na(Pupcare), TRUE, CHECK)) %>%
    rename("Pup care" = "Pupcare")

  ## ----GA-------------------------------------------------------------------------------------------------------------------------------------------------------------
  dataGA <- data %>%
    mutate(GA_only = ifelse(grepl("GA", Behavior), Behavior, NA)) %>%
    filter(!is.na(GA_only)) %>%
    mutate(End = if_else(grepl("GA; End", Behavior), "TRUE", " ")) %>%
    mutate(Followed = if_else(grepl("GA; End", lead(Behavior)), "TRUE", " ")) %>%
    mutate(End.Sec = case_when(Followed != "TRUE" & End != "TRUE" ~ St.Sec + 1,
                               Followed == "TRUE" ~ lead(St.Sec))) %>%
    mutate(Duration = End.Sec - St.Sec) %>%
    mutate(Modifiers = ifelse(Followed == "TRUE", lead(Modifiers), Modifiers)) %>%
    mutate(removerow = ifelse(is.na(CHECK) & grepl("GA; End", Behavior), TRUE, removerow)) %>%
    mutate(Comments = ifelse(lead(removerow) == TRUE & !is.na(lead(Comments)), lead(Comments), Comments)) %>%
    select(Date, St.Sec, End.Sec, Duration, Behavior, OG_order, Modifiers, Comments, removerow, CHECK)

  ## ----GT-------------------------------------------------------------------------------------------------------------------------------------------------------------
  dataGT <- data %>%
    mutate(GT_only = ifelse(grepl("GT", Behavior), TRUE, NA)) %>%
    mutate(GT_and_following = ifelse(grepl("GT", Behavior) & grepl("GT", lag(Behavior)) &
                                       !grepl("GT other", Behavior), Behavior, NA)) %>%
    filter(!is.na(GT_and_following)) %>%
    mutate(End = if_else(grepl("GT; End", Behavior), "TRUE", " ")) %>%
    mutate(Followed = if_else(grepl("GT; End", lead(Behavior)), "TRUE", " ")) %>%
    mutate(End.Sec = case_when(GT_only == TRUE & Followed != "TRUE" & End != "TRUE" ~ lead(St.Sec),
                               GT_only == TRUE & Followed == "TRUE" ~ lead(St.Sec))) %>%
    mutate(Duration = End.Sec - St.Sec) %>%
    mutate(Modifiers = ifelse(Followed == "TRUE", lead(Modifiers), Modifiers)) %>%
    mutate(removerow = ifelse(is.na(CHECK) & grepl("GT; End", Behavior), TRUE, removerow)) %>%
    mutate(Comments = ifelse(lead(removerow) == TRUE & !is.na(lead(Comments)), lead(Comments), Comments)) %>%
    select(Date, St.Sec, End.Sec, Duration, Behavior, OG_order, Modifiers, removerow, Comments, CHECK)

  ## ----Burr/BH--------------------------------------------------------------------------------------------------------------------------------------------------------
  dataBurrBH <- data %>%
    mutate(BurrBH_only = ifelse(grepl("Burr/BH renn", Behavior), TRUE, NA)) %>%
    mutate(BurrBH_and_following = ifelse(grepl("Burr/BH renn", Behavior) |
                                           grepl("Burr/BH renn", lag(Behavior)), Behavior, NA)) %>%
    filter(!is.na(BurrBH_and_following)) %>%
    mutate(End = if_else(grepl("Burr/BH renn; End", Behavior), "TRUE", " ")) %>%
    mutate(Followed = if_else(grepl("Burr/BH renn; End", lead(Behavior)), "TRUE", " ")) %>%
    mutate(End.Sec = case_when(BurrBH_only == TRUE & Followed != "TRUE" & End != "TRUE" ~ lead(St.Sec),
                               BurrBH_only == TRUE & Followed == "TRUE" & End != "TRUE" ~ lead(St.Sec))) %>%
    mutate(Duration = End.Sec - St.Sec) %>%
    mutate(Modifiers = ifelse(BurrBH_only == TRUE & Followed == "TRUE" & End != "TRUE", lead(Modifiers), Modifiers)) %>%
    mutate(removerow = ifelse(is.na(CHECK) & grepl("Burr/BH renn; End", Behavior), TRUE, removerow)) %>%
    filter(BurrBH_only) %>%
    mutate(Comments = ifelse(lead(removerow) == TRUE & !is.na(lead(Comments)), lead(Comments), Comments)) %>%
    select(Date, St.Sec, End.Sec, Duration, Behavior, OG_order, Modifiers, Comments, removerow, CHECK)


  ## ----InBurrBH-------------------------------------------------------------------------------------------------------------------------------------------------------
  dataInBurr <- data %>%
    mutate(InBurr_only = ifelse(grepl("In burr/BH", Behavior), Behavior, NA)) %>%
    mutate(EndFocal_next = ifelse(grepl("End Focal", lead(Behavior)), Behavior, NA)) %>%
    filter(!is.na(InBurr_only)) %>%
    mutate(End = if_else(grepl("In burr/BH; End", Behavior), "TRUE", " ")) %>%
    mutate(Followed = if_else(grepl("In burr/BH; End", lead(Behavior)), "TRUE", " ")) %>%
    mutate(End.Sec = case_when(Followed == "TRUE" & End != "TRUE" ~ lead(St.Sec))) %>%
    mutate(CHECK = if_else(Followed != "TRUE" & End != "TRUE", TRUE, CHECK)) %>%
    mutate(Duration = End.Sec - St.Sec) %>%
    mutate(Modifiers = ifelse(Followed == "TRUE" & End != "TRUE", lead(Modifiers), Modifiers)) %>%
    mutate(removerow = ifelse(is.na(CHECK) & grepl("In burr/BH; End", Behavior), TRUE, removerow)) %>%
    mutate(Comments = ifelse(lead(removerow) == TRUE & !is.na(lead(Comments)), lead(Comments), Comments)) %>%
    select(Date, St.Sec, End.Sec, Duration, Behavior, OG_order, Modifiers, Comments, removerow, CHECK)


  ## ----OutOfView------------------------------------------------------------------------------------------------------------------------------------------------------
  dataOOV <- data %>%
    mutate(OOV_only = ifelse(grepl("Out of view", Behavior), Behavior, NA)) %>%
    mutate(EndFocal_next = ifelse(grepl("End Focal", lead(Behavior)), Behavior, NA)) %>%
    filter(!is.na(OOV_only)) %>%
    mutate(End = if_else(grepl("Out of view; End", Behavior), "TRUE", " ")) %>%
    mutate(Followed = if_else(grepl("Out of view; End", lead(Behavior)), "TRUE", " ")) %>%
    mutate(End.Sec = case_when(Followed == "TRUE" & End != "TRUE" ~ lead(St.Sec))) %>%
    mutate(CHECK = if_else(Followed != "TRUE" & End != "TRUE", TRUE, NA)) %>%
    mutate(Duration = End.Sec - St.Sec) %>%
    mutate(Modifiers = ifelse(Followed == "TRUE" & End != "TRUE", lead(Modifiers), Modifiers)) %>%
    mutate(removerow = ifelse(is.na(CHECK) & grepl("Out of view; End", Behavior), TRUE, removerow)) %>%
    mutate(Comments = ifelse(lead(removerow) == TRUE & !is.na(lead(Comments)), lead(Comments), Comments)) %>%
    select(Date, St.Sec, End.Sec, Duration, Behavior, OG_order, Modifiers, Comments, removerow, CHECK)


  ## ----Dig------------------------------------------------------------------------------------------------------------------------------------------------------------
  dataFirstJoin <- data %>%
    filter(!(grepl("Nearest neigh.|Other vig.", Behavior) & str_count(Behavior, ";") == 0)) %>%
    mutate(Dig_only = ifelse(grepl("Dig", Behavior) | grepl("Re-Dig", Behavior), Behavior, NA)) %>%
    mutate(End_only = ifelse(Behavior == "End (+Modifiers)", Behavior, NA)) %>%
    mutate(Followed = case_when(!grepl("Dig; End", Behavior) & grepl("End|Dig", lead(Behavior)) & grepl("Dig", Behavior) ~ "TRUE",
                                !grepl("Re-Dig; End", Behavior) & grepl("End|Re-Dig", lead(Behavior)) & grepl("Re-Dig", Behavior) ~ "TRUE",
                                TRUE ~ "")) %>%
    mutate(Dig_followed_by_other = NA) %>%
    mutate(Dig_followed_by_other = ifelse(!is.na(Dig_only) & !grepl("End", Behavior) & Followed != "TRUE", TRUE, NA)) %>%
    mutate(End.Sec = ifelse(Dig_followed_by_other == TRUE, lead(St.Sec), End.Sec)) %>%
    mutate(Duration = End.Sec - St.Sec) %>%
    filter(!is.na(Dig_followed_by_other)) %>%
    select(Date, St.Sec, OG_order, End.Sec, Duration, Behavior, Modifiers, Comments, removerow, Dig_followed_by_other, CHECK)

  data <- right_join(dataFirstJoin, data, by = c("Date", "St.Sec", "OG_order")) %>%
    rename(End.Sec = "End.Sec.x", Duration = "Duration.x", removerow = "removerow.x", Modifiers = "Modifiers.x", CHECK = "CHECK.x", Behavior = "Behavior.x", Comments = "Comments.x",) %>%
    subset(is.na(removerow)) %>%
    mutate(Modifiers = ifelse(is.na(Modifiers) & !is.na(Modifiers.y), Modifiers.y, Modifiers)) %>%
    mutate(Behavior = ifelse(is.na(Behavior) & !is.na(Behavior.y), Behavior.y, Behavior)) %>%
    mutate(End.Sec = ifelse(is.na(End.Sec) & !is.na(End.Sec.y), End.Sec.y, End.Sec)) %>%
    mutate(Duration = ifelse(is.na(Duration) & !is.na(Duration.y), Duration.y, Duration)) %>%
    mutate(removerow = ifelse(is.na(removerow) & !is.na(removerow.y), removerow.y, removerow)) %>%
    mutate(CHECK = ifelse(is.na(CHECK) & !is.na(CHECK.y), CHECK.y, CHECK)) %>%
    mutate(Comments = ifelse(is.na(Comments) & !is.na(Comments.y), Comments.y, Comments)) %>%
    arrange(OG_order) %>%
    select(-Modifiers.y, -End.Sec.y, -Duration.y, -removerow.y, -CHECK.y, -Comments.y, -Behavior.y)

  dataDig <- data %>%
    mutate(mult_sizes_CHECK = NA) %>%
    filter(is.na(Dig_followed_by_other)) %>%
    mutate(Dig_only = ifelse(grepl("Dig", Behavior) | grepl("Re-Dig", Behavior), Behavior, NA)) %>%
    mutate(End_only = ifelse(Behavior == "End (+Modifiers)", Behavior, NA)) %>%
    filter(!is.na(Dig_only) | !is.na(End_only)) %>%
    mutate(End = if_else(grepl("Dig; End", Behavior) | grepl("Re-Dig; End", Behavior), "TRUE", " ")) %>%
    mutate(Followed = case_when(!grepl("Dig; End", Behavior) & grepl("Dig; End", lead(Behavior)) ~ "TRUE",
                                !grepl("Re-Dig; End", Behavior) & grepl("Re-Dig; End", lead(Behavior)) ~ "TRUE",
                                TRUE ~ "")) %>%
    mutate(End.Sec = case_when(Followed != "TRUE" & End != "TRUE" & is.na(End_only) ~ St.Sec + 1,
                               Followed == "TRUE" & is.na(End_only) ~ lead(St.Sec))) %>%
    mutate(Duration = End.Sec - St.Sec) %>%
    mutate(Modifiers = case_when(Followed == "TRUE" & grepl("Tiny|Small|Medium|Large", lead(Modifiers)) ~ lead(Modifiers),
                                 Followed == "TRUE" & is.na(End_only) & grepl("Tiny|Small|Medium|Large", lead(Modifiers)) == FALSE ~ "success",
                                 TRUE ~ Modifiers)) %>%
    mutate(StrCount = ifelse(End == "TRUE", str_count(Modifiers, ';'), NA)) %>%
    mutate(Behavior = case_when(End == "TRUE" & grepl("Small", Modifiers) & StrCount <= 1 ~ "d.small",
                                End == "TRUE" & grepl("Medium", Modifiers) & StrCount <= 1 ~ "d.medium",
                                End == "TRUE" & grepl("Large", Modifiers) & StrCount <= 1 ~ "d.large",
                                End == "TRUE" & grepl("1; Tiny|2; Tiny|Tiny; <5", Modifiers) & StrCount <= 1 ~ "d.tiny.few",
                                End == "TRUE" & Modifiers == "Tiny; >5" & StrCount <= 1 ~ "d.tiny.many",
                                End == "TRUE" & Modifiers == "Tiny" & StrCount <= 1 ~ "d.tiny",
                                TRUE ~ Behavior)) %>%
    mutate(CHECK = case_when(grepl("Dig; End", Behavior) & Behavior != "Re-Dig; End (+Modifiers)" & Behavior != "Other vig.; Re-Dig; End (+Modifiers)" & Behavior != "Dig; End (+Modifiers)" & Behavior != "Re-Dig; End (+Modifiers)" & Behavior != "Other vig.; Dig; End (+Modifiers)" ~ TRUE,
                             TRUE ~ CHECK)) %>%
    mutate(mult_sizes_CHECK = ifelse(End == "TRUE" & StrCount > 1, TRUE, NA)) %>%
    mutate(removerow = case_when(is.na(CHECK) & Behavior == "Dig; End (+Modifiers)" &
                                   grepl("Tiny|Small|Medium|Large", Modifiers) == FALSE ~ TRUE,
                                 is.na(CHECK) & Behavior == "Re-Dig; End (+Modifiers)" &
                                   grepl("Tiny|Small|Medium|Large", Modifiers) == FALSE ~ TRUE,
                                 is.na(CHECK) & Behavior == "Dig; End (+Modifiers)" &
                                   grepl("Dig; End (+Modifiers)", lag(Modifiers)) ~ TRUE,
                                 is.na(CHECK) & Behavior == "Dig; End (+Modifiers)" &
                                   grepl("Re-Dig; End (+Modifiers)", lag(Modifiers)) ~ TRUE,
                                 TRUE ~ removerow)) %>%
    mutate(Comments = ifelse(lead(removerow) == TRUE & !is.na(lead(Comments)), lead(Comments), Comments)) %>%
    select(Date, St.Sec, End.Sec, Duration, Behavior, OG_order, Modifiers, removerow, Comments, CHECK, mult_sizes_CHECK)

  ## ----joining-dataframes---------------------------------------------------------------------------------------------------------------------------------------------
  data <- data %>%
    select(-Dig_followed_by_other)

  datajoin <- right_join(dataGA, data, by = c("Date", "St.Sec", "OG_order")) %>%
    rename(End.Sec = "End.Sec.x", Duration = "Duration.x", removerow = "removerow.x", Modifiers = "Modifiers.x", CHECK = "CHECK.x", Behavior = "Behavior.x", Comments = "Comments.x",) %>%
    subset(is.na(removerow)) %>%
    mutate(Modifiers = ifelse(is.na(Modifiers) & !is.na(Modifiers.y), Modifiers.y, Modifiers)) %>%
    mutate(Behavior = ifelse(is.na(Behavior) & !is.na(Behavior.y), Behavior.y, Behavior)) %>%
    mutate(End.Sec = ifelse(is.na(End.Sec) & !is.na(End.Sec.y), End.Sec.y, End.Sec)) %>%
    mutate(Duration = ifelse(is.na(Duration) & !is.na(Duration.y), Duration.y, Duration)) %>%
    mutate(removerow = ifelse(is.na(removerow) & !is.na(removerow.y), removerow.y, removerow)) %>%
    mutate(CHECK = ifelse(is.na(CHECK) & !is.na(CHECK.y), CHECK.y, CHECK)) %>%
    mutate(Comments = ifelse(is.na(Comments) & !is.na(Comments.y), Comments.y, Comments)) %>%
    arrange(OG_order) %>%
    select(-Modifiers.y, -End.Sec.y, -Duration.y, -removerow.y, -CHECK.y, -Comments.y, -Behavior.y) %>%
    right_join(dataInBurr, ., by = c("Date", "St.Sec", "OG_order")) %>%
    rename(End.Sec = "End.Sec.x", Duration = "Duration.x", removerow = "removerow.x", Modifiers = "Modifiers.x", CHECK = "CHECK.x", Behavior = "Behavior.x", Comments = "Comments.x") %>%
    subset(is.na(removerow)) %>%
    mutate(Modifiers = ifelse(is.na(Modifiers) & !is.na(Modifiers.y), Modifiers.y, Modifiers)) %>%
    mutate(Behavior = ifelse(is.na(Behavior) & !is.na(Behavior.y), Behavior.y, Behavior)) %>%
    mutate(End.Sec = ifelse(is.na(End.Sec) & !is.na(End.Sec.y), End.Sec.y, End.Sec)) %>%
    mutate(Duration = ifelse(is.na(Duration) & !is.na(Duration.y), Duration.y, Duration)) %>%
    mutate(removerow = ifelse(is.na(removerow) & !is.na(removerow.y), removerow.y, removerow)) %>%
    mutate(CHECK = ifelse(is.na(CHECK) & !is.na(CHECK.y), CHECK.y, CHECK)) %>%
    mutate(Comments = ifelse(is.na(Comments) & !is.na(Comments.y), Comments.y, Comments)) %>%
    arrange(OG_order) %>%
    select(-Modifiers.y, -End.Sec.y, -Duration.y, -removerow.y, -CHECK.y, -Comments.y, -Behavior.y) %>%
    right_join(dataGT, ., by = c("Date", "St.Sec", "OG_order")) %>%
    rename(End.Sec = "End.Sec.x", Duration = "Duration.x", removerow = "removerow.x", Modifiers = "Modifiers.x", CHECK = "CHECK.x", Behavior = "Behavior.x", Comments = "Comments.x") %>%
    subset(is.na(removerow)) %>%
    mutate(Modifiers = ifelse(is.na(Modifiers) & !is.na(Modifiers.y), Modifiers.y, Modifiers)) %>%
    mutate(Behavior = ifelse(is.na(Behavior) & !is.na(Behavior.y), Behavior.y, Behavior)) %>%
    mutate(End.Sec = ifelse(is.na(End.Sec) & !is.na(End.Sec.y), End.Sec.y, End.Sec)) %>%
    mutate(Duration = ifelse(is.na(Duration) & !is.na(Duration.y), Duration.y, Duration)) %>%
    mutate(removerow = ifelse(is.na(removerow) & !is.na(removerow.y), removerow.y, removerow)) %>%
    mutate(CHECK = ifelse(is.na(CHECK) & !is.na(CHECK.y), CHECK.y, CHECK)) %>%
    mutate(Comments = ifelse(is.na(Comments) & !is.na(Comments.y), Comments.y, Comments)) %>%
    arrange(OG_order) %>%
    select(-Modifiers.y, -End.Sec.y, -Duration.y, -removerow.y, -CHECK.y, -Comments.y, -Behavior.y) %>%
    right_join(dataBurrBH, ., by = c("Date", "St.Sec", "OG_order")) %>%
    rename(End.Sec = "End.Sec.x", Duration = "Duration.x", removerow = "removerow.x", Modifiers = "Modifiers.x", CHECK = "CHECK.x", Behavior = "Behavior.x", Comments = "Comments.x") %>%
    subset(is.na(removerow)) %>%
    mutate(Modifiers = ifelse(is.na(Modifiers) & !is.na(Modifiers.y), Modifiers.y, Modifiers)) %>%
    mutate(Behavior = ifelse(is.na(Behavior) & !is.na(Behavior.y), Behavior.y, Behavior)) %>%
    mutate(End.Sec = ifelse(is.na(End.Sec) & !is.na(End.Sec.y), End.Sec.y, End.Sec)) %>%
    mutate(Duration = ifelse(is.na(Duration) & !is.na(Duration.y), Duration.y, Duration)) %>%
    mutate(removerow = ifelse(is.na(removerow) & !is.na(removerow.y), removerow.y, removerow)) %>%
    mutate(CHECK = ifelse(is.na(CHECK) & !is.na(CHECK.y), CHECK.y, CHECK)) %>%
    mutate(Comments = ifelse(is.na(Comments) & !is.na(Comments.y), Comments.y, Comments)) %>%
    arrange(OG_order) %>%
    select(-Modifiers.y, -End.Sec.y, -Duration.y, -removerow.y, -CHECK.y, -Comments.y, -Behavior.y) %>%
    right_join(dataOOV, ., by = c("Date", "St.Sec", "OG_order")) %>%
    rename(End.Sec = "End.Sec.x", Duration = "Duration.x", removerow = "removerow.x", Modifiers = "Modifiers.x", CHECK = "CHECK.x", Behavior = "Behavior.x", Comments = "Comments.x") %>%
    subset(is.na(removerow)) %>%
    mutate(Modifiers = ifelse(is.na(Modifiers) & !is.na(Modifiers.y), Modifiers.y, Modifiers)) %>%
    mutate(Behavior = ifelse(is.na(Behavior) & !is.na(Behavior.y), Behavior.y, Behavior)) %>%
    mutate(End.Sec = ifelse(is.na(End.Sec) & !is.na(End.Sec.y), End.Sec.y, End.Sec)) %>%
    mutate(Duration = ifelse(is.na(Duration) & !is.na(Duration.y), Duration.y, Duration)) %>%
    mutate(removerow = ifelse(is.na(removerow) & !is.na(removerow.y), removerow.y, removerow)) %>%
    mutate(CHECK = ifelse(is.na(CHECK) & !is.na(CHECK.y), CHECK.y, CHECK)) %>%
    mutate(Comments = ifelse(is.na(Comments) & !is.na(Comments.y), Comments.y, Comments)) %>%
    arrange(OG_order) %>%
    select(-Modifiers.y, -End.Sec.y, -Duration.y, -removerow.y, -CHECK.y, -Comments.y, -Behavior.y) %>%
    right_join(dataDig, ., by = c("Date", "St.Sec", "OG_order")) %>%
    rename(End.Sec = "End.Sec.x", Duration = "Duration.x", removerow = "removerow.x", Modifiers = "Modifiers.x", CHECK = "CHECK.x", Behavior = "Behavior.x", Comments = "Comments.x") %>%
    subset(is.na(removerow)) %>%
    mutate(Modifiers = ifelse(is.na(Modifiers) & !is.na(Modifiers.y), Modifiers.y, Modifiers)) %>%
    mutate(Behavior = ifelse(is.na(Behavior) & !is.na(Behavior.y), Behavior.y, Behavior)) %>%
    mutate(End.Sec = ifelse(is.na(End.Sec) & !is.na(End.Sec.y), End.Sec.y, End.Sec)) %>%
    mutate(Duration = ifelse(is.na(Duration) & !is.na(Duration.y), Duration.y, Duration)) %>%
    mutate(removerow = ifelse(is.na(removerow) & !is.na(removerow.y), removerow.y, removerow)) %>%
    mutate(CHECK = ifelse(is.na(CHECK) & !is.na(CHECK.y), CHECK.y, CHECK)) %>%
    mutate(Comments = ifelse(is.na(Comments) & !is.na(Comments.y), Comments.y, Comments)) %>%
    arrange(OG_order) %>%
    select(-Modifiers.y, -End.Sec.y, -Duration.y, -removerow.y, -CHECK.y, -Behavior.y, -Comments.y)

  ## ----DigEndModifier-------------------------------------------------------------------------------------------------------------------------------------------------
  DurData <- datajoin %>%
    mutate(End_only = ifelse(Behavior == "End (+Modifiers)", TRUE, NA)) %>%
    mutate(End_DigMod = ifelse(Behavior == "End (+Modifiers)" & grepl("Tiny|Small|Medium|Large", Modifiers), TRUE, NA)) %>%
    mutate(Dig_only = ifelse(grepl("Dig", Behavior) | grepl("Re-Dig", Behavior), Behavior, NA)) %>%
    mutate(End = if_else(grepl("Dig; End", Behavior) | grepl("Re-Dig; End", Behavior), "TRUE", " ")) %>%
    mutate(EndNearEnd = case_when(End_DigMod == TRUE & grepl("Dig; End", lag(Behavior)) ~ "1st case",
                                  End_DigMod == TRUE & grepl("Re-Dig; End", lag(Behavior)) ~ "1st case",
                                  End_DigMod == TRUE & grepl("Other vig.|Nearest neigh.", lag(Behavior)) &
                                    grepl("Dig; End", lag(Behavior, n = 2)) ~ "2nd case",
                                  End_DigMod == TRUE & grepl("Other vig.|Nearest neigh.", lag(Behavior)) &
                                    grepl("Re-Dig; End", lag(Behavior, n = 2)) ~ "2nd case",
                                  End_DigMod == TRUE & grepl("Other vig.|Nearest neigh.", lag(Behavior)) &
                                    grepl("Other vig.|Nearest neigh.", lag(Behavior, n = 2)) & grepl("Dig; End", lag(Behavior, n = 3)) ~ "3rd case",
                                  End_DigMod == TRUE & grepl("Other vig.|Nearest neigh.", lag(Behavior)) & grepl("Other vig.|Nearest neigh.", lag(Behavior, n = 2)) & grepl("Re-Dig; End", lag(Behavior, n = 3)) ~ "3rd case")) %>%
    mutate(EndNotNearEnd = case_when(End_DigMod == TRUE & is.na(EndNearEnd) ~ TRUE)) %>%
    mutate(CHECK = case_when(End_only == TRUE & is.na(End_DigMod) ~ TRUE, TRUE ~ CHECK))

  DurData <- DurData %>%
    mutate(dupDig = FALSE)
  DigToDup <- DurData %>%
    filter(!is.na(EndNearEnd) | !is.na(EndNotNearEnd)) %>%
    mutate(dupDig = TRUE)

  DurData <- rbindlist(list(DigToDup, DurData))[order(OG_order)]
  DurData <- DurData %>%
    mutate(StrCount = ifelse(dupDig == "TRUE", str_count(Modifiers, ';'), NA)) %>%
    mutate(Behavior = case_when(is.na(EndNearEnd) != TRUE & dupDig == "TRUE" & grepl("Small", Modifiers) & StrCount <= 1 ~ "d.small",
                                is.na(EndNearEnd) != TRUE & dupDig == "TRUE" & grepl("Medium", Modifiers) & StrCount <= 1 ~ "d.medium",
                                is.na(EndNearEnd) != TRUE & dupDig == "TRUE" & grepl("Large", Modifiers) & StrCount <= 1 ~ "d.large",
                                is.na(EndNearEnd) != TRUE & dupDig == "TRUE" & grepl("1; Tiny|2; Tiny|Tiny; <5", Modifiers) & StrCount <= 1 ~ "d.tiny.few",
                                is.na(EndNearEnd) != TRUE & dupDig == "TRUE" & Modifiers == "Tiny; >5" & StrCount <= 1 ~ "d.tiny.many",
                                TRUE ~ Behavior)) %>%
    mutate(Behavior = case_when(EndNotNearEnd == TRUE & dupDig == "TRUE" & grepl("Small", Modifiers) & StrCount <= 1 ~ "fa.small",
                                EndNotNearEnd == TRUE & dupDig == "TRUE" & grepl("Medium", Modifiers) & StrCount <= 1 ~ "fa.medium",
                                EndNotNearEnd == TRUE & dupDig == "TRUE" & grepl("Large", Modifiers) & StrCount <= 1 ~ "fa.large",
                                EndNotNearEnd == TRUE & dupDig == "TRUE" & grepl("1; Tiny|2; Tiny|Tiny; <5", Modifiers) & StrCount <= 1 ~ "fa.tiny.few",
                                EndNotNearEnd == TRUE & dupDig == "TRUE" & Modifiers == "Tiny; >5" & StrCount <= 1 ~ "fa.tiny.many",
                                TRUE ~ Behavior)) %>%
    mutate(mult_sizes_CHECK = case_when(StrCount > 1 ~ TRUE,
                                        TRUE ~ mult_sizes_CHECK)) %>%
    select(-End_only, -End_DigMod, -Dig_only, -End, -EndNearEnd, -EndNotNearEnd, -StrCount, -dupDig)

  ## ----Duplicate_multiple_size_modifiers------------------------------------------------------------------------------------------------------------------------------
  DurData <- DurData %>%
    mutate(StrCount = str_count(Modifiers, ';')) %>%
    mutate(HasSmall = ifelse(grepl("Small", Modifiers), "Small", NA)) %>%
    mutate(HasMedium = ifelse(grepl("Medium", Modifiers), "Medium", NA)) %>%
    mutate(HasLarge = ifelse(grepl("Large", Modifiers), "Large", NA)) %>%
    mutate(CHECK = ifelse(grepl("Tiny", Modifiers) & is.na(HasSmall) & is.na(HasMedium) & is.na(HasLarge) & StrCount > 1, TRUE, CHECK)) %>%
    mutate(TwoTinysCHECK = ifelse(grepl("Tiny", Modifiers) & is.na(HasSmall) & is.na(HasMedium) & is.na(HasLarge) & StrCount > 1, TRUE, NA)) %>%
    mutate(Modifiers2 = ifelse(mult_sizes_CHECK == TRUE, str_remove_all(DurData$Modifiers2, "Small|Medium|Large|Tiny"), NA)) %>%
    mutate(CHECK = ifelse(grepl("[a-zA-Z]", Modifiers2), TRUE, CHECK)) %>%
    select(-Modifiers2)

  ModifierToDup <- DurData %>%
    filter(!is.na(mult_sizes_CHECK) & is.na(CHECK)) %>%
    mutate(StrCount = str_count(Modifiers, ';')) %>%
    mutate(HasSmall = ifelse(grepl("Small", Modifiers), "Small", NA)) %>%
    mutate(HasMedium = ifelse(grepl("Medium", Modifiers), "Medium", NA)) %>%
    mutate(HasLarge = ifelse(grepl("Large", Modifiers), "Large", NA)) %>%
    mutate(HasTinyFew = ifelse(grepl("1; Tiny|2; Tiny|Tiny; <5", Modifiers), "TinyFew", NA)) %>%
    mutate(HasTinyMany = ifelse(grepl("Tiny; >5", Modifiers), "TinyMany", NA))

  ModifierToDup <- ModifierToDup %>%
    unite("TotalMods", HasSmall, HasMedium, HasLarge, HasTinyFew, HasTinyMany, sep = "; ", remove = TRUE, na.rm = TRUE) %>%
    mutate(Modifiers = ifelse(is.na(CHECK), TotalMods, Modifiers)) %>%
    separate_rows(Modifiers, sep = "; ") %>%
    mutate(Behavior = case_when(grepl("Small", Modifiers) ~ "d.small",
                                grepl("Medium", Modifiers) ~ "d.medium",
                                grepl("Large", Modifiers) ~ "d.large",
                                grepl("TinyFew", Modifiers) ~ "d.tiny.few",
                                Modifiers == "TinyMany"  ~ "d.tiny.many",
                                Modifiers == "Tiny" ~ "d.tiny",
                                TRUE ~ Behavior)) %>%
    select(-StrCount, -TotalMods, -mult_sizes_CHECK)

  DurData <- subset(DurData, is.na(TwoTinysCHECK) & is.na(mult_sizes_CHECK))
  DurData <- DurData %>% select(-mult_sizes_CHECK, -TwoTinysCHECK, -HasSmall, -HasMedium, -HasLarge, -StrCount)
  ModifierToDup <- ModifierToDup %>% select(-TwoTinysCHECK)

  if(nrow(ModifierToDup) != 0) {
    DurData <- rbindlist(list(ModifierToDup, DurData), fill = TRUE)[order(OG_order)]
  }


  ## ----dictionary-----------------------------------------------------------------------------------------------------------------------------------------------------
  dictionary <- read_excel("data/dictionary.xlsx")


  ## ----special-cases-before-separating--------------------------------------------------------------------------------------------------------------------------------
  data <- DurData %>%
    mutate(hasIR = grepl("Initiate; ", Play) | grepl("Receive; ", Play)) %>%
    mutate(oneSemi = hasIR == TRUE & str_count(Play, ";") == 1) %>%
    mutate(receiveFirst = grepl("^Receive; ", Play)) %>%
    mutate(Play = case_when(hasIR == TRUE ~ gsubfn("Initiate;|Receive;",
                                                   list("Initiate;" = "Initiate",
                                                        "Receive;" = "Receive"), Play), TRUE ~ Play)) %>%
    mutate(Play = case_when(receiveFirst == TRUE & oneSemi == FALSE &
                              grepl("Initiate", Play) == FALSE ~
                              gsub(";", "; Receive", Play), TRUE ~ Play)) %>%
    select(-c(hasIR, oneSemi, receiveFirst))

  data <- data %>%
    mutate(hasIR = grepl("Initiate; ", AggSub) | grepl("Receive; ", AggSub)) %>%
    mutate(oneSemi = hasIR == TRUE & str_count(AggSub, ";") == 1) %>%
    mutate(receiveFirst = grepl("^Receive; ", AggSub)) %>%
    mutate(AggSub = case_when(hasIR == TRUE ~ gsubfn("Initiate;|Receive;",
                                                     list("Initiate;" = "Initiate",
                                                          "Receive;" = "Receive"), AggSub), TRUE ~ AggSub)) %>%
    mutate(AggSub = case_when(receiveFirst == TRUE & oneSemi == FALSE &
                                grepl("Initiate", Play) == FALSE ~
                                gsub(";", "; Receive", AggSub), TRUE ~ AggSub)) %>%
    select(-c(hasIR, oneSemi, receiveFirst))

  data <- data %>%
    mutate(hasIR = grepl("Initiate; ", Olfactory) | grepl("Receive; ", Olfactory)) %>%
    mutate(oneSemi = hasIR == TRUE & str_count(Olfactory, ";") == 1) %>%
    mutate(receiveFirst = grepl("^Receive; ", Olfactory)) %>%
    mutate(Olfactory = case_when(hasIR == TRUE ~ gsubfn("Initiate;|Receive;",
                                                        list("Initiate;" = "Initiate",
                                                             "Receive;" = "Receive"), Olfactory), TRUE ~ Olfactory)) %>%
    mutate(Olfactory = case_when(receiveFirst == TRUE & oneSemi == FALSE &
                                   grepl("Initiate", Play) == FALSE ~
                                   gsub(";", "; Receive", Olfactory), TRUE ~ Olfactory)) %>%
    select(-c(hasIR, oneSemi, receiveFirst))

  data <- data %>%
    mutate(wrestle = grepl("Wrestle", Play)) %>%
    mutate(Play = case_when(wrestle == TRUE ~ gsubfn("Wrestle; Bottom|Wrestle; Top",
                                                     list("Wrestle; Bottom" = "Wrestle Bottom",
                                                          "Wrestle; Top" = "Wrestle Top"), Play),
                            TRUE ~ Play)) %>%
    select(-wrestle)


  ## ----separate-rows--------------------------------------------------------------------------------------------------------------------------------------------------
  data <- data %>%
    separate_rows(AggSub, Play, Olfactory, sep = ";") %>%
    trim(AggSub) %>%
    mutate(AggSub = case_when(((AggSub == "Lose" | AggSub == "Win" | AggSub == "Unclear winner") &
                                 grepl("Fcomp", lag(AggSub)) == TRUE) ~
                                str_c(lag(AggSub), sep = " ", AggSub), TRUE ~ AggSub)) %>%
    unite("OB", AggSub, Play, Olfactory, sep = "; ", remove = FALSE, na.rm = TRUE) %>%
    separate_rows(OB, sep = "; ")


  ## ----fix-behavior-values--------------------------------------------------------------------------------------------------------------------------------------------
  ##For values in behavior column not standard, duplicate row
  data <- data %>%
    mutate(dupBehavior = FALSE)

  behaviorToDup <- data %>%
    filter(OB != "") %>%
    mutate(isBehavior = ifelse(Behavior == "Aggr./Sub." | Behavior == "Play" | Behavior == "Olfactory", TRUE, FALSE)) %>%
    filter(isBehavior == FALSE) %>%
    mutate(dupBehavior = TRUE) %>%
    select(-isBehavior)

  data <- rbindlist(list(behaviorToDup, data))[order(OG_order)]

  data <- data %>%
    mutate(Behavior = case_when(dupBehavior == TRUE ~ "is behavior", TRUE ~ Behavior)) %>%
    select(-dupBehavior)



  ## ----OB-into-behavior-col-------------------------------------------------------------------------------------------------------------------------------------------
  data <- data %>%
    mutate(Behavior = case_when(Behavior == "Aggr./Sub." |
                                  Behavior == "Olfactory" | Behavior == "Play" |
                                  Behavior == "is behavior" ~ OB, TRUE ~ Behavior))


  ## ----Behaviors_with_Approach_in_BehaviorCol-------------------------------------------------------------------------------------------------------------------------
  data <- data %>%
    mutate(HasApproach = ifelse(grepl("^Approach", Behavior) | grepl("^Receive approach", Behavior), TRUE, FALSE)) %>%
    mutate(StrCount = ifelse(HasApproach == TRUE & str_count(Behavior, ';') != 0, TRUE, NA)) %>%
    mutate(Split = ifelse(HasApproach == TRUE & StrCount == TRUE, TRUE, FALSE)) %>%
    mutate(BehaviorToSplit = ifelse(Split == TRUE, Behavior, NA)) %>%
    separate_rows(BehaviorToSplit, sep = ";") %>%
    mutate(Behavior = ifelse(!is.na(BehaviorToSplit), BehaviorToSplit, Behavior)) %>%
    select(-Split, -BehaviorToSplit, -StrCount)


  ## ----replace-by-dictionary------------------------------------------------------------------------------------------------------------------------------------------
  data <- data %>%
    trim(Behavior)

  inds <- match(tolower(data$Behavior), tolower(dictionary$Behavior))
  data$Behavior[!is.na(inds)] <- dictionary$replacement[na.omit(inds)]


  ## ----Split_Initiate_&_Receive_in-Partner(s)---------------------------------------------------------------------------------------------------------------------
  data <- data %>% rename_at(vars(ends_with('partner(s)')), ~"Partner")

  data <- data %>%
    mutate(ToDup = FALSE) %>%
    mutate(HasApproach = ifelse(grepl("^Approach", Behavior) | grepl("^Receive approach", Behavior), TRUE, FALSE)) %>%
    mutate(ToReceive = ifelse(grepl("Receive|Recieve", Partner) & HasApproach == FALSE & OB == "", TRUE, NA)) %>%
    mutate(InitiateAndReceive = ifelse(ToReceive == TRUE & (grepl("Reciprocate", Partner) | grepl("Initiate", Partner)), TRUE, NA)) %>%
    mutate(Partner = ifelse(InitiateAndReceive == TRUE, str_remove(Partner, "Receive;|Recieve;"), Partner))

  behaviorToDup <- data %>%
    filter(InitiateAndReceive == TRUE) %>%
    mutate(Partner = ifelse(grepl("Reciprocate", Partner), str_replace(Partner, "Reciprocate", "Receive"), Partner)) %>%
    mutate(Partner = ifelse(grepl("Initiate", Partner), str_replace(Partner, "Initiate", "Receive"), Partner)) %>%
    mutate(ToDup = TRUE) %>%
    trim(Behavior)

  behaviorToDup <- behaviorToDup %>%
    mutate(Behavior = ifelse(ToDup == TRUE & grepl("^i.", Behavior), str_replace(Behavior, "i.", "r."), NA))

  data <- rbindlist(list(behaviorToDup, data))[order(OG_order)]

  ## -------------------------------------------------------------------------------------------------------------------------------------------------------------------
  data <- data %>%
    mutate(End.Time = as_hms(End.Sec)) %>%
    mutate(St.Time = as_hms(St.Sec)) %>%
    rename(S.Duration = "Duration") %>%
    mutate(Duration = as_hms(S.Duration)) %>%
    mutate(Date = gsub(" 12:00:00 AM", "", Date)) %>%
    rename("Aggression/Submission" = "AggSub") %>%
    rename_at(vars(starts_with('Time...')), ~"Time") %>%
    rename_at(vars(ends_with('Partner')), ~"Partner(s)") %>%
    mutate(Date = format(as.Date(Date), "%m/%d/%Y")) %>%
    select(-removerow, -OB, -St.Sec, -OG_order, -End.Sec, -ToDup, -HasApproach, -ToReceive, -InitiateAndReceive)

  setcolorder(data, c("Focal.ID", "Location", "Date", "St.Time", "End.Time", "Duration", "S.Duration", "Observer",
                      "Groups", "KMP.ID", "Focal individual", "Behavior", "Partner(s)", "Aggression/Submission",
                      "Olfactory", "Play", "Pup care", "Sex", "Modifiers", "Life History", "Time",
                      "Time spent running", "Comments", "CHECK"))
  ## -------------------------------------------------------------------------------------------------------------------------------------------------------------------

  newlist[[n]] <- as.data.frame(data)
  names(newlist)[n] <- n
}

sheetnamesvec <- excel_sheets("data/Pup8MoIndividual_copy_for_ys.xlsx")
names(newlist) <- sheetnamesvec[2:59]
write.xlsx(newlist, "Pup8MoIndividual_ys_v9.xlsx", append = TRUE)
